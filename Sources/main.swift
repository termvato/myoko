import AppKit
import ServiceManagement
import SwiftUI

// All the timing lives here. Change a number and rerun build.sh.
let eyeEvery: Double = 20 * 60        // look far away every 20 minutes...
let eyeRest = Double(ProcessInfo.processInfo.environment["MYOKO_EYE_SECONDS"] ?? "") ?? 20   // ...for 20 seconds
let walkLock: Double = 2 * 60         // the takeover holds the screen this long for a walk
let walkEvery: Double = 60 * 60       // little walk every hour
let eyeSnooze: Double = 5 * 60
let walkSnooze: Double = 10 * 60
let awayAfter: Double = 5 * 60        // no input this long, and no video playing, means you already took a break

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 28)
    private let launched = Date()
    private var lastTick = Date()
    private var eyeElapsed: Double = 0
    private var walkElapsed: Double = 0
    private var pausedUntil: Date?
    private var walkingUntil: Date?
    private var isAway = false
    private var lastFrameKey = ""
    private var imageCache: [String: NSImage] = [:]
    private var activity: NSObjectProtocol?

    private let model = PopupModel()
    private var panel: PopupPanel?
    private var eyeFinish: Timer?
    private var celebrationEnd: Timer?
    private var active: BreakKind?
    private var celebrating = false
    private var invasion: Invasion?
    private var breakStart = Date()

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let resumeItem = NSMenuItem(title: "resume", action: #selector(resume), keyEquivalent: "")
    private let soundItem = NSMenuItem(title: "sounds", action: #selector(toggleSound), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "open at login", action: #selector(toggleLogin), keyEquivalent: "")
    private let invadeItem = NSMenuItem(title: "take over the screen", action: #selector(toggleInvade), keyEquivalent: "")
    private let characterMenu = NSMenu()

    private var soundOn: Bool {
        get { UserDefaults.standard.object(forKey: "sound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sound") }
    }

    private var invadeOn: Bool {
        get { UserDefaults.standard.object(forKey: "invade") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "invade") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        Sprite.mascot = Mascot(rawValue: UserDefaults.standard.string(forKey: "mascot") ?? "") ?? .eyeball
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "break timers")
        statusItem.autosaveName = "MyokoStatusItem"
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "myoko"
        buildMenu()
        renderStatus()

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.renderStatus() }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(resetTimers), name: NSWorkspace.didWakeNotification, object: nil)

        // Handy for trying the popups without waiting.
        let args = CommandLine.arguments
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if args.contains("--eye-now") { self?.show(.eyes) }
            if args.contains("--walk-now") { self?.show(.walk) }
        }
    }

    // MARK: Timers

    private func tick() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now

        if let until = pausedUntil, until > now { return }
        pausedUntil = nil

        // A long gap means the Mac was asleep.
        if delta > 60 { resetTimers(); return }

        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        // A playing video still counts as screen time.
        isAway = idle >= awayAfter && !VideoWatch.isPlaying()
        if isAway {
            resetTimers()
            return
        }

        guard active == nil else { return }
        eyeElapsed += delta
        walkElapsed += delta

        if walkElapsed >= walkEvery {
            show(.walk)
        } else if eyeElapsed >= eyeEvery {
            show(.eyes)
        }
    }

    @objc private func resetTimers() {
        eyeElapsed = 0
        walkElapsed = 0
        lastTick = Date()
    }

    // MARK: Menu bar sprite

    private var currentMood: Mood {
        let now = Date()
        if celebrating { return .happy }
        if let active { return active == .eyes ? .lookFar : .alert }
        if let until = walkingUntil, until > now { return .walk }
        if pausedUntil != nil || isAway { return .sleep }
        return .idle
    }

    private func renderStatus() {
        let t = Date().timeIntervalSince(launched)
        let mood = currentMood
        // The eye reddens towards the next break, then clears during it.
        if active == .eyes {
            // A takeover rests your eyes only after its warning, so stay red until then.
            let restStart = breakStart.addingTimeInterval(invasion == nil ? 0 : Invasion.warningSeconds)
            Sprite.strain = min(1, max(0, 1 - Date().timeIntervalSince(restStart) / eyeRest))
        } else {
            Sprite.strain = min(1, eyeElapsed / eyeEvery)
        }
        let grid = Sprite.grid(mood: mood, t: t)
        let key = String(grid.flatMap { $0 })
        guard key != lastFrameKey else { return }
        lastFrameKey = key

        let image = imageCache[key] ?? {
            let img = NSImage(size: NSSize(width: 24, height: 25.5), flipped: true) { _ in
                guard let c = NSGraphicsContext.current?.cgContext else { return false }
                // 1.5pt per sprite pixel is exactly 3 device pixels on a Retina screen.
                Sprite.draw(in: c, x: 0, y: 0, scale: 1.5, mood: mood, t: t)
                return true
            }
            imageCache[key] = img
            return img
        }()
        statusItem.button?.image = image
    }

    // MARK: Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        pauseLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(pauseLine)
        menu.addItem(.separator())
        menu.addItem(item("look far now", #selector(eyeNow)))
        menu.addItem(item("walk now", #selector(walkNow)))
        menu.addItem(.separator())
        menu.addItem(item("pause for 30 min", #selector(nap30)))
        menu.addItem(item("pause for 1 hour", #selector(nap60)))
        resumeItem.target = self
        menu.addItem(resumeItem)
        menu.addItem(.separator())
        soundItem.target = self
        loginItem.target = self
        invadeItem.target = self
        let characterItem = NSMenuItem(title: "character", action: nil, keyEquivalent: "")
        for mascot in Mascot.allCases {
            let i = item(mascot.rawValue, #selector(pickMascot(_:)))
            i.representedObject = mascot.rawValue
            characterMenu.addItem(i)
        }
        characterItem.submenu = characterMenu
        menu.addItem(characterItem)
        menu.addItem(invadeItem)
        menu.addItem(soundItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("quit myoko", #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    private func minutes(_ seconds: Double) -> String {
        let m = Int(ceil(max(0, seconds) / 60))
        return "\(m) min"
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let until = pausedUntil, until > Date() {
            statusLine.title = "paused for \(minutes(until.timeIntervalSinceNow))"
            pauseLine.isHidden = true
            resumeItem.isHidden = false
        } else {
            statusLine.title = "look far in \(minutes(eyeEvery - eyeElapsed))"
            pauseLine.title = "walk in \(minutes(walkEvery - walkElapsed))"
            pauseLine.isHidden = false
            resumeItem.isHidden = true
        }
        soundItem.state = soundOn ? .on : .off
        invadeItem.state = invadeOn ? .on : .off
        for i in characterMenu.items {
            i.state = (i.representedObject as? String) == Sprite.mascot.rawValue ? .on : .off
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func eyeNow() { show(.eyes) }
    @objc private func walkNow() { show(.walk) }
    @objc private func nap30() { nap(30 * 60) }
    @objc private func nap60() { nap(60 * 60) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleSound() { soundOn.toggle() }
    @objc private func toggleInvade() { invadeOn.toggle() }
    @objc private func pickMascot(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mascot = Mascot(rawValue: raw) else { return }
        Sprite.mascot = mascot
        UserDefaults.standard.set(raw, forKey: "mascot")
    }

    private func nap(_ seconds: Double) {
        closePopup()
        pausedUntil = Date().addingTimeInterval(seconds)
        resetTimers()
    }

    @objc private func resume() {
        pausedUntil = nil
        resetTimers()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    // MARK: Popups

    private func show(_ kind: BreakKind) {
        closePopup()
        active = kind
        walkingUntil = nil
        pausedUntil = nil
        breakStart = Date()

        // Never blow up a video call: during one, fall back to the small popup.
        if invadeOn && !MeetingGuard.isInMeeting() {
            invade(kind)
            return
        }

        model.kind = kind
        model.done = false
        model.start = Date()
        model.duration = eyeRest
        switch kind {
        case .eyes:
            model.title = ["eyes up.", "look far.", "window. now."].randomElement()!
            model.subtitle = "pick something far away, 6 m or more. hold it for 20 seconds."
        case .walk:
            model.title = ["go walk.", "legs check.", "time to move."].randomElement()!
            model.subtitle = "you've been sitting for an hour. a few minutes is enough."
        }
        chime("Tink")
        presentPanel()

        if kind == .eyes {
            eyeFinish = Timer.scheduledTimer(withTimeInterval: eyeRest, repeats: false) { [weak self] _ in
                self?.finishEyes()
            }
        }
    }

    private func invade(_ kind: BreakKind) {
        chime("Tink")
        let takeover = Invasion(
            kind: kind,
            duration: kind == .eyes ? eyeRest : walkLock,
            onFinished: { [weak self] in
                guard let self else { return }
                self.eyeElapsed = 0
                if kind == .walk { self.walkElapsed = 0 }
                self.chime("Glass")
                self.closePopup()
            },
            onBail: { [weak self] in self?.skip() },
            onSnooze: { [weak self] in self?.snooze() }
        )
        invasion = takeover
        takeover.start()
    }

    private func presentPanel() {
        let view = PopupView(
            model: model,
            onSkip: { [weak self] in self?.skip() },
            onSnooze: { [weak self] in self?.snooze() },
            onWalking: { [weak self] in self?.startWalking() }
        )
        let host = FirstClickHostingView(rootView: view)
        let size = host.fittingSize
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let bounds = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var anchor = statusItem.button?.window?.frame ?? .zero
        // If macOS can't say where the icon is, sit at the top right, below the menu bar.
        if anchor.width == 0 || anchor.minY < bounds.midY {
            let top = screen?.visibleFrame.maxY ?? bounds.maxY
            anchor = NSRect(x: bounds.maxX - 200, y: top, width: 28, height: 0)
        }
        let x = min(max(anchor.midX - size.width / 2, bounds.minX + 8), bounds.maxX - size.width - 8)
        let y = anchor.minY - size.height - 2
        model.pointerX = anchor.midX - x

        let p = PopupPanel(contentRect: NSRect(x: x, y: y + 8, width: size.width, height: size.height),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentView = host
        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1
            p.animator().setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func finishEyes() {
        eyeFinish?.invalidate()
        eyeElapsed = 0
        chime("Glass")
        celebrate("done.", "next one in 20 min.")
    }

    private func celebrate(_ title: String, _ subtitle: String) {
        celebrating = true
        model.done = true
        model.title = title
        model.subtitle = subtitle
        celebrationEnd = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.closePopup()
        }
    }

    private func skip() {
        if active == .walk { walkElapsed = 0 } else { eyeElapsed = 0 }
        closePopup()
    }

    private func snooze() {
        if active == .walk {
            walkElapsed = walkEvery - walkSnooze
        } else {
            eyeElapsed = eyeEvery - eyeSnooze
        }
        closePopup()
    }

    private func startWalking() {
        walkElapsed = 0
        eyeElapsed = 0   // a walk rests your eyes as well
        walkingUntil = Date().addingTimeInterval(120)
        chime("Glass")
        celebrate("good.", "myoko will hold the fort.")
    }

    private func closePopup() {
        invasion?.stop()
        invasion = nil
        eyeFinish?.invalidate()
        eyeFinish = nil
        celebrationEnd?.invalidate()
        celebrationEnd = nil
        panel?.orderOut(nil)
        panel = nil
        active = nil
        celebrating = false
    }

    private func chime(_ name: String) {
        guard soundOn else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
