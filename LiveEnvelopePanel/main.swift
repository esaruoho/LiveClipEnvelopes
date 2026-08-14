// LiveEnvelopePanel — a small always-on-top, non-activating panel of buttons that
// drive live-envelope. Every button just shells out to the same binary the
// Keyboard Maestro macros use, so behaviour is identical either way.
//
// Panel buttons, top to bottom:
//   Transpose:  -12 | 0 | +12        (relative nudge / absolute reset via AbletonOSC)
//   Envelope:   Gain | Transpose | Sample Offset   (direct select, no toggling)
// A status line along the bottom shows the last result or error.
//
// Keyboard, while the panel is focused (it is the frontmost window, so this needs no
// event tap, no Accessibility permission and no hover detection):
//   <-  ->    Prev / Next envelope   — same as the buttons
//   ^   v     step the transposition ladder by an octave, i.e. along the top row:
//             -48 -36 -24 -12 0 +12 +24 +36 +48
//             This is a relative nudge, and AbletonOSC's nudge_clip_transposition
//             already clamps to Live's -48..48, so the ends need no handling here.
// Without this, AppKit has nothing to route an arrow key to and macOS just beeps.

import Cocoa
import ApplicationServices

//--------------------------------------------------------------------------------
// Where live-envelope lives. The same probe order the Keyboard Maestro macros use:
// an installed copy first, so a customer's machine works, with the dev checkout last.
// Hardcoding a single path meant the app only ever worked on the author's machine.
//--------------------------------------------------------------------------------
// The copy inside the app bundle comes first: it is signed as part of the app, so it
// runs under the app's single code identity and the app's Accessibility grant covers
// it. An external /usr/local/bin copy is a separate binary with its own identity, and
// is only kept for the Keyboard Maestro macros and Shortcuts to call.
let BIN_CANDIDATES = [
    Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/live-envelope").path,
    "/usr/local/bin/live-envelope",
    "/opt/homebrew/bin/live-envelope",
    NSHomeDirectory() + "/.local/bin/live-envelope",
    NSHomeDirectory() + "/work/apple/bin/live-envelope",
]

func liveEnvelopeBinary() -> String? {
    BIN_CANDIDATES.first { FileManager.default.isExecutableFile(atPath: $0) }
}

//--------------------------------------------------------------------------------
// AbletonOSC preflight. The app needs AbletonOSC installed AND carrying this
// project's extra handlers; without them the OSC writes are fire-and-forget UDP into
// nothing, so buttons appear to work while silently doing nothing at all.
//
// Both checks are pure filesystem reads — deterministic, no sockets, no ports to
// clash over, and meaningful even when Live is not running.
//--------------------------------------------------------------------------------
enum AbletonOSCStatus {
    case ok
    case notInstalled
    case notPatched(missing: [String])

    var isOK: Bool { if case .ok = self { return true }; return false }

    var summary: String {
        switch self {
        case .ok: return "AbletonOSC installed and patched"
        case .notInstalled: return "AbletonOSC is not installed"
        case .notPatched(let missing):
            return "AbletonOSC is missing this project's patch (\(missing.count) handler\(missing.count == 1 ? "" : "s"))"
        }
    }
}

enum AbletonOSC {
    static let requiredHandlers = [
        "show_clip_envelope", "hide_clip_envelope",
        "nudge_clip_transposition", "set_clip_transposition",
    ]

    /// Live reads Remote Scripts from the shared User Library, so this path serves
    /// every installed Live version.
    static var scriptDirectory: String {
        NSHomeDirectory() + "/Music/Ableton/User Library/Remote Scripts/AbletonOSC"
    }

    static func check() -> AbletonOSCStatus {
        let viewFile = scriptDirectory + "/abletonosc/view.py"
        guard FileManager.default.fileExists(atPath: viewFile) else { return .notInstalled }
        guard let source = try? String(contentsOfFile: viewFile, encoding: .utf8) else {
            return .notPatched(missing: requiredHandlers)
        }
        let missing = requiredHandlers.filter { !source.contains("/live/view/\($0)") }
        return missing.isEmpty ? .ok : .notPatched(missing: missing)
    }
}

let PANEL_WIDTH: CGFloat = 460
/// Breathing room between the window edge and the buttons, horizontally and vertically.
let PANEL_INSET_X: CGFloat = 14
let PANEL_INSET_Y: CGFloat = 12

//--------------------------------------------------------------------------------
// Accessibility permission. live-envelope drives Live through the accessibility API,
// and a child process is judged by its parent's grant — so it is THIS app that has to
// be trusted, and this app that has to ask.
//
// The catch that makes asking essential: the app is ad-hoc signed, so TCC pins the
// grant to the binary's cdhash. Any rebuild or update produces a new cdhash and the
// existing grant silently stops matching — System Settings still shows the checkbox
// ticked while AXIsProcessTrusted() returns false. The only cure is to remove the
// stale entry and add it again, which no user would ever guess. Hence the banner,
// the system prompt, and the explicit instructions in the alert below.
//--------------------------------------------------------------------------------
enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// The system's own "…would like to control this computer" dialog.
    static func systemPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// So the app can be dragged into the Accessibility list when adding it by hand.
    static func revealInFinder() {
        NSWorkspace.shared.selectFile(Bundle.main.bundlePath,
                                      inFileViewerRootedAtPath: "/Applications")
    }
}

func runLiveEnvelope(_ args: [String], completion: @escaping (String, Bool) -> Void) {
    guard let binary = liveEnvelopeBinary() else {
        DispatchQueue.main.async {
            completion("live-envelope not found — run install.sh", false)
        }
        return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = args
    let outPipe = Pipe(), errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    process.terminationHandler = { proc in
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let ok = proc.terminationStatus == 0
        let text = ok ? out.trimmingCharacters(in: .whitespacesAndNewlines)
                      : err.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async { completion(text, ok) }
    }
    do {
        try process.run()
    } catch {
        DispatchQueue.main.async { completion("failed to launch live-envelope: \(error)", false) }
    }
}

let DEFAULT_TITLE = "Live Clip Envelopes"

/// US-layout virtual key codes for the arrow keys.
let KEY_LEFT = 123, KEY_RIGHT = 124, KEY_DOWN = 125, KEY_UP = 126

final class PanelController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    //--------------------------------------------------------------------------------
    // Bumped on every press; a delayed revert-to-default only applies if it's still
    // the most recent press, so a rapid second click isn't stomped by the first
    // click's timer reverting the title out from under it.
    //--------------------------------------------------------------------------------
    var generation = 0

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PANEL_WIDTH, height: 100),
            styleMask: [.nonactivatingPanel, .titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false)

        super.init()

        //--------------------------------------------------------------------------------
        // The app's name lives in the title bar, not as a row of button-area text, so it
        // costs no vertical space. The title also doubles as the result/error readout.
        //--------------------------------------------------------------------------------
        panel.title = DEFAULT_TITLE
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false

        //--------------------------------------------------------------------------------
        // No section labels: the button captions ("Gain", "+12", ...) already say what
        // each one does, so a header above them would only repeat that and cost a row.
        //--------------------------------------------------------------------------------
        root.addArrangedSubview(row([
            smallButton("-48", "transpose-set-neg48"),
            smallButton("-36", "transpose-set-neg36"),
            smallButton("-24", "transpose-set-neg24"),
            smallButton("-12", "transpose-down-12"),
            smallButton("0", "transpose-set-0"),
            smallButton("+12", "transpose-up-12"),
            smallButton("+24", "transpose-set-24"),
            smallButton("+36", "transpose-set-36"),
            smallButton("+48", "transpose-set-48"),
            menuButton(),
        ]))

        root.addArrangedSubview(row([
            button("◀ Prev", "prev"),
            button("Gain", "exact Gain"),
            button("Transpose", "exact Transposition"),
            button("Sample Offset", "exact Sample Offset"),
            button("Next ▶", "next"),
        ]))

        rootStack = root
        // Right-click anywhere on the panel offers the same commands.
        root.menu = buildActionMenu()

        panel.contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView!.menu = buildActionMenu()
        panel.contentView!.addSubview(root)
        //--------------------------------------------------------------------------------
        // Inset with real constraint constants rather than NSStackView.edgeInsets, which
        // AppKit ignored here: the buttons ended up flush with the window and in fact 1pt
        // PAST it on both sides. Measured before: left/right margin = -1.0.
        //--------------------------------------------------------------------------------
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor,
                                          constant: PANEL_INSET_X),
            root.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor,
                                           constant: -PANEL_INSET_X),
            root.topAnchor.constraint(equalTo: panel.contentView!.topAnchor,
                                      constant: PANEL_INSET_Y),
            root.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor,
                                         constant: -PANEL_INSET_Y),
        ])

        //--------------------------------------------------------------------------------
        // Fixed width, always. Nothing inside — including a long error message in the
        // status field — is allowed to grow the window; only its height can adapt.
        //--------------------------------------------------------------------------------
        panel.minSize = NSSize(width: PANEL_WIDTH, height: 0)
        panel.maxSize = NSSize(width: PANEL_WIDTH, height: .greatestFiniteMagnitude)

        //--------------------------------------------------------------------------------
        // Size to exactly what the two button rows need, rather than a guessed constant
        // — this is what keeps the window free of dead space.
        //--------------------------------------------------------------------------------
        root.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: PANEL_WIDTH,
                                    height: root.fittingSize.height + PANEL_INSET_Y * 2))

        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        installKeyboardMonitor()
        startWatchingAccessibility()

        //--------------------------------------------------------------------------------
        // A .nonactivatingPanel deliberately does NOT make the app active when clicked —
        // that is what keeps focus in Live while using the buttons. The side effect is
        // that the app's menu bar (About / Support / Help) never appears on its own, so
        // activate once at launch to put it on screen.
        //--------------------------------------------------------------------------------
        NSApp.activate()
    }

    //--------------------------------------------------------------------------------
    // Permission banner: a row that only exists while the app is untrusted, so the
    // problem is visible on the panel itself rather than a status message that times
    // out. Without this the app looks broken and gives no way to fix it.
    //--------------------------------------------------------------------------------
    private var permissionRow: NSStackView?
    private var permissionTimer: Timer?
    private var rootStack: NSStackView?
    private var permissionAlertOpen = false
    private var oscRow: NSStackView?

    private func makePermissionRow() -> NSStackView {
        let warning = NSTextField(labelWithString: "⚠︎ Needs Accessibility permission to control Live")
        warning.font = .systemFont(ofSize: 11, weight: .medium)
        warning.lineBreakMode = .byTruncatingTail

        let fix = NSButton(title: "Grant Access…", target: self, action: #selector(grantAccessPressed))
        fix.bezelStyle = .rounded
        fix.font = .systemFont(ofSize: 11)
        fix.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [warning, fix])
        row.orientation = .horizontal
        row.spacing = 8
        row.distribution = .fill
        return row
    }

    /// TCC changes arrive with no notification, so poll — cheaply, and only while
    /// untrusted; once granted the timer stops and never runs again.
    private func startWatchingAccessibility() {
        refreshPermissionRow()
        guard !Accessibility.isTrusted else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if Accessibility.isTrusted {
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
                self.refreshPermissionRow()
                self.panel.title = "Accessibility granted — ready"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.generation == 0 { self.panel.title = DEFAULT_TITLE }
                }
            }
        }
    }

    private func refreshPermissionRow() {
        guard let root = rootStack else { return }
        let trusted = Accessibility.isTrusted
        if trusted {
            permissionRow?.removeFromSuperview()
            permissionRow = nil
        } else if permissionRow == nil {
            let row = makePermissionRow()
            permissionRow = row
            root.insertArrangedSubview(row, at: 0)
        }

        //--------------------------------------------------------------------------------
        // A missing or unpatched AbletonOSC is just as fatal as a missing permission, and
        // even harder to notice: the OSC writes are one-way, so buttons look like they
        // worked. Checked once at startup — it is a filesystem state that cannot change
        // without a reinstall and a Live restart anyway.
        //--------------------------------------------------------------------------------
        if oscRow == nil, case let status = AbletonOSC.check(), !status.isOK {
            let warning = NSTextField(labelWithString: "⚠︎ " + status.summary)
            warning.font = .systemFont(ofSize: 11, weight: .medium)
            warning.lineBreakMode = .byTruncatingTail
            let help = NSButton(title: "Fix…", target: self, action: #selector(setupPressed))
            help.bezelStyle = .rounded
            help.font = .systemFont(ofSize: 11)
            help.setContentHuggingPriority(.required, for: .horizontal)
            let row = NSStackView(views: [warning, help])
            row.orientation = .horizontal
            row.spacing = 8
            oscRow = row
            root.insertArrangedSubview(row, at: permissionRow == nil ? 0 : 1)
        }
        root.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: PANEL_WIDTH,
                                    height: root.fittingSize.height + PANEL_INSET_Y * 2))
    }

    /// One place that answers "is this machine actually set up?", reachable from the
    /// menu so it can be checked before a demo rather than discovered during one.
    func showSetupReport() {
        NSApp.activate()   // same reason as showAccessibilityAlert()
        let trusted = Accessibility.isTrusted
        let osc = AbletonOSC.check()
        let binary = liveEnvelopeBinary()
        let liveRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.ableton.live").isEmpty

        func mark(_ good: Bool) -> String { good ? "✓" : "✗" }

        let alert = NSAlert()
        var problems: [String] = []
        if !trusted { problems.append("Accessibility permission") }
        if binary == nil { problems.append("live-envelope binary") }
        if !osc.isOK { problems.append("AbletonOSC") }

        alert.alertStyle = problems.isEmpty ? .informational : .warning
        alert.messageText = problems.isEmpty
            ? "Everything is set up"
            : "Not ready: " + problems.joined(separator: ", ")
        alert.informativeText = """
            \(mark(trusted)) Accessibility permission \(trusted ? "granted" : "MISSING — needed to read Live's UI")
            \(mark(binary != nil)) live-envelope \(binary ?? "NOT FOUND — reinstall with install.sh")
            \(mark(osc.isOK)) \(osc.summary)
                \(AbletonOSC.scriptDirectory)
            \(mark(liveRunning)) Ableton Live \(liveRunning ? "running" : "not running")

            AbletonOSC must be installed there AND carry this project's patch, otherwise \
            transposition and revealing the Envelopes box silently do nothing — the OSC \
            messages are one-way, so nothing reports the failure.
            """
        alert.addButton(withTitle: "OK")
        if !osc.isOK { alert.addButton(withTitle: "AbletonOSC Setup Help") }
        alert.beginSheetModal(for: panel) { response in
            if response == .alertSecondButtonReturn,
               let url = URL(string: HELP_URL + "#abletonosc-setup") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func setupPressed() { showSetupReport() }

    //--------------------------------------------------------------------------------
    // Problem row. The window title truncates at the panel's fixed width, so a message
    // like "…Select an audio clip and open Clip View" lost exactly the half that says
    // what to do. This shows the whole text, wrapped, with a button that goes to the
    // place the text is talking about.
    //--------------------------------------------------------------------------------
    private var problemRow: NSStackView?
    private var problemLabel: NSTextField?
    private var problemButton: NSButton?

    private enum ProblemAction: Equatable {
        case showLive, grantAccess, checkSetup, none

        var title: String? {
            switch self {
            case .showLive:    return "Show Live"
            case .grantAccess: return "Grant Access…"
            case .checkSetup:  return "Check Setup…"
            case .none:        return nil
            }
        }
    }

    /// Picks the action from what the CLI actually said, so the button always points at
    /// the thing that is wrong rather than at a generic help page.
    private func action(for text: String) -> ProblemAction {
        let lower = text.lowercased()
        if lower.contains("not trusted") { return .grantAccess }
        if lower.contains("not found") { return .checkSetup }
        if lower.contains("no envelopes box") || lower.contains("live is not running")
            || lower.contains("clip view") || lower.contains("audio clip") { return .showLive }
        return .none
    }

    private var currentProblemAction: ProblemAction = .none

    func showProblem(_ text: String) {
        guard let root = rootStack else { return }
        currentProblemAction = action(for: text)

        if problemRow == nil {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 11)
            label.maximumNumberOfLines = 3
            label.preferredMaxLayoutWidth = PANEL_WIDTH - 130
            label.textColor = .secondaryLabelColor
            let button = NSButton(title: "", target: self, action: #selector(problemActionPressed))
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 11)
            button.setContentHuggingPriority(.required, for: .horizontal)
            let row = NSStackView(views: [label, button])
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .centerY
            problemLabel = label
            problemButton = button
            problemRow = row
            root.addArrangedSubview(row)
        }
        problemLabel?.stringValue = text
        //--------------------------------------------------------------------------------
        // Do not show a second "Grant Access…" when the banner above is already offering
        // it — one problem, one button.
        //--------------------------------------------------------------------------------
        if currentProblemAction == .grantAccess && permissionRow != nil {
            problemButton?.isHidden = true
        } else if let title = currentProblemAction.title {
            problemButton?.title = title
            problemButton?.isHidden = false
        } else {
            problemButton?.isHidden = true
        }
        resizeToFit()
    }

    func clearProblem() {
        guard problemRow != nil else { return }
        problemRow?.removeFromSuperview()
        problemRow = nil
        problemLabel = nil
        problemButton = nil
        resizeToFit()
    }

    @objc private func problemActionPressed() {
        switch currentProblemAction {
        case .grantAccess: grantAccessPressed()
        case .checkSetup:  showSetupReport()
        case .showLive:
            //--------------------------------------------------------------------------------
            // Bring Live forward so the clip can be picked. Launch it if it is not running —
            // the panel is non-activating, so Live keeps focus and the next click lands there.
            //--------------------------------------------------------------------------------
            if let live = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.ableton.live").first {
                live.activate()
            } else if let url = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: "com.ableton.live") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        case .none: break
        }
    }

    private func resizeToFit() {
        guard let root = rootStack else { return }
        root.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: PANEL_WIDTH,
                                    height: root.fittingSize.height + PANEL_INSET_Y * 2))
    }

    @objc private func grantAccessPressed() {
        //--------------------------------------------------------------------------------
        // Fire the system prompt first: on a machine that has never granted anything it
        // adds the app to the list on its own, which is the shortest path. It is a no-op
        // once an entry already exists, which is exactly the stale-grant case the alert
        // below explains.
        //--------------------------------------------------------------------------------
        NSApp.activate()
        Accessibility.systemPrompt()
        //--------------------------------------------------------------------------------
        // Deliberately deferred: the system prompt is a separate window, and putting our
        // alert up in the same turn buries one behind the other.
        //--------------------------------------------------------------------------------
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.showAccessibilityAlert()
        }
    }

    func showAccessibilityAlert() {
        //--------------------------------------------------------------------------------
        // Activate first. A .nonactivatingPanel app can be inactive while runModal() runs,
        // which starts a modal loop with the alert stacked behind other windows: the panel
        // then ignores every click and looks frozen with no way out.
        //--------------------------------------------------------------------------------
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Live Envelopes needs Accessibility permission"
        alert.informativeText = """
            It drives Ableton Live's Clip View through macOS's accessibility API, which \
            macOS requires you to allow explicitly.

            In System Settings ▸ Privacy & Security ▸ Accessibility:

            1. If “Live Envelopes” is NOT listed, click + and add it from /Applications.
            2. If it IS listed, switch it OFF and back ON — or remove it with − and add \
            it again. After an app update the old permission no longer matches the new \
            build, even though the switch still looks on.
            3. Come back here — the warning disappears by itself once it works.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Show App in Finder")
        alert.addButton(withTitle: "Later")

        alert.beginSheetModal(for: panel) { response in
            switch response {
            case .alertFirstButtonReturn:  Accessibility.openSettings()
            case .alertSecondButtonReturn: Accessibility.revealInFinder()
            default: break
            }
        }
    }

    /// The panel is the app: closing it quits. Nothing else does — in particular no
    /// menu item other than Quit, and no window opened by one (About, a browser).
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        NSApp.terminate(nil)
    }

    //--------------------------------------------------------------------------------
    // Arrow keys, handled with a local event monitor rather than a keyDown override:
    // the monitor sees the event whichever control happens to be first responder, so a
    // button that has picked up focus from an earlier click cannot swallow the arrow
    // (AppKit would otherwise use it to move focus between buttons).
    //
    // Returning nil consumes the event, which is also what stops the beep.
    //--------------------------------------------------------------------------------
    private func installKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            //--------------------------------------------------------------------------------
            // Let anything with a modifier through untouched, so Cmd-Q, Cmd-W and the like
            // still reach the menu.
            //--------------------------------------------------------------------------------
            let modifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            guard event.modifierFlags.intersection(modifiers).isEmpty else { return event }

            switch Int(event.keyCode) {
            case KEY_LEFT:  self.perform(["prev"]);              return nil
            case KEY_RIGHT: self.perform(["next"]);              return nil
            case KEY_UP:    self.perform(["transpose-up-12"]);   return nil
            case KEY_DOWN:  self.perform(["transpose-down-12"]); return nil
            default:        return event
            }
        }
    }

    /// Opens the action menu on a plain left-click, so About / Support / Help are one
    /// click away even though the panel never activates the app.
    func menuButton() -> NSButton {
        let button = NSButton(title: "⋯", target: self, action: #selector(showActionMenu(_:)))
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 10)
        button.toolTip = "About, Support, Help, Check Setup"
        return button
    }

    @objc func showActionMenu(_ sender: NSButton) {
        let menu = buildActionMenu()
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.height + 4),
                   in: sender)
    }

    func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.distribution = .fillEqually
        return stack
    }

    func button(_ title: String, _ args: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(pressed(_:)))
        button.bezelStyle = .rounded
        button.tag = commandTable.count
        commandTable.append(args)
        return button
    }

    /// A row of nine needs a smaller font to stay legible at the panel's fixed width.
    func smallButton(_ title: String, _ args: String) -> NSButton {
        let button = self.button(title, args)
        button.font = .systemFont(ofSize: 10)
        return button
    }

    var commandTable: [String] = []

    @objc func pressed(_ sender: NSButton) {
        perform(commandTable[sender.tag].split(separator: " ").map(String.init))
    }

    /// Runs one `live-envelope` command and reports it in the title. Shared by the
    /// buttons and the arrow keys so both paths behave identically.
    func perform(_ args: [String]) {
        generation += 1
        let thisPress = generation

        runLiveEnvelope(args) { [weak self] text, ok in
            guard let self = self else { return }
            //--------------------------------------------------------------------------------
            // Keep the title short: it truncates. The full message lives in the problem row.
            //--------------------------------------------------------------------------------
            if ok {
                self.panel.title = text.isEmpty ? DEFAULT_TITLE : text
                self.clearProblem()
            } else {
                self.panel.title = DEFAULT_TITLE
                self.showProblem(text)
            }

            //--------------------------------------------------------------------------------
            // A permission failure is the one error a status line cannot resolve: it needs an
            // action from the user, and the message scrolls away before they can read it. Put
            // the banner back and offer the fix directly, once per press rather than per key
            // repeat, so holding a button can't stack up alerts.
            //--------------------------------------------------------------------------------
            if !ok && text.localizedCaseInsensitiveContains("not trusted") {
                self.refreshPermissionRow()
                if !self.permissionAlertOpen {
                    self.permissionAlertOpen = true
                    self.showAccessibilityAlert()
                    self.permissionAlertOpen = false
                    self.startWatchingAccessibility()
                }
                return
            }
            //--------------------------------------------------------------------------------
            // An error stays up longer than a success, since it's the one worth reading.
            //--------------------------------------------------------------------------------
            let holdSeconds = ok ? 1.5 : 5.0
            DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) {
                if self.generation == thisPress { self.panel.title = DEFAULT_TITLE }
            }
        }
    }
}

//--------------------------------------------------------------------------------
// Menu bar. The app previously had a single unnamed menu holding only Quit, so there
// was nowhere for About, Help or the support links to live. A .regular activation
// policy already gives us a menu bar; it just had nothing in it.
//--------------------------------------------------------------------------------
let SUPPORT_LINKS: [(String, String)] = [
    ("Ko-fi", "https://ko-fi.com/esaruoho"),
    ("BuyMeACoffee", "https://buymeacoffee.com/esaruoho"),
    ("PayPal", "https://www.paypal.me/esaruoho"),
    ("GitHub Sponsors", "https://github.com/sponsors/esaruoho"),
    ("Patreon", "http://patreon.com/esaruoho"),
    ("Bandcamp (buy the music)", "http://lackluster.bandcamp.com/"),
]
let HELP_URL = "https://github.com/esaruoho/LiveClipEnvelopes"
let STORE_URL = "https://lackluster.gumroad.com/l/liveclipenvelopes"
let CONTACT_EMAIL = "esaruoho@gmail.com"

final class MenuActions: NSObject {
    @objc func openURL(_ sender: NSMenuItem) {
        guard let string = sender.representedObject as? String,
              let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func showAbout(_ sender: Any?) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Live Clip Envelopes",
            .applicationVersion: version,
            .credits: aboutCredits(),
        ])
    }

    //--------------------------------------------------------------------------------
    // The About panel renders an NSAttributedString, so every one of these is a real
    // clickable link. Telling someone "the Support menu keeps it alive" and making them
    // go find it is a dead end when the links can simply be here.
    //--------------------------------------------------------------------------------
    private func aboutCredits() -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: 11)
        let bold = NSFont.boldSystemFont(ofSize: 11)
        let text = NSMutableAttributedString()

        func add(_ string: String, font: NSFont = NSFont.systemFont(ofSize: 11)) {
            text.append(NSAttributedString(string: string, attributes: [.font: font]))
        }

        func addLink(_ label: String, _ urlString: String) {
            guard let url = URL(string: urlString) else { return add(label) }
            text.append(NSAttributedString(string: label, attributes: [
                .font: body,
                .link: url,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]))
        }

        /// Joins links with a separator, so a row reads "A · B · C".
        func addLinkRow(_ links: [(String, String)]) {
            for (index, entry) in links.enumerated() {
                if index > 0 { add("  ·  ") }
                addLink(entry.0, entry.1)
            }
        }

        add("""
            Drive Ableton Live's Clip View envelope choosers — Gain, Transposition and \
            Sample Offset — plus Link/Unlink and clip transposition, from buttons, keyboard \
            shortcuts, Keyboard Maestro macros or Shortcuts.

            By Lackluster (Esa Ruoho)

            """)

        add("Get it / rate it\n", font: bold)
        addLinkRow([("Live Clip Envelopes on Gumroad", STORE_URL)])
        add("\n\n")

        add("Support the work\n", font: bold)
        addLinkRow(SUPPORT_LINKS.map { ($0.0, $0.1) })
        add("\n\n")

        add("Help & contact\n", font: bold)
        addLinkRow([
            ("Documentation", HELP_URL),
            ("Report an issue", HELP_URL + "/issues"),
            ("Email Esa", "mailto:" + CONTACT_EMAIL),
        ])

        return text
    }

    @objc func checkPermission(_ sender: Any?) {
        panelController?.showAccessibilityAlert()
    }

    @objc func checkSetup(_ sender: Any?) {
        panelController?.showSetupReport()
    }
}

let menuActions = MenuActions()
/// Set once the panel exists, so menu items can talk to it.
var panelController: PanelController?

//--------------------------------------------------------------------------------
// The same commands as a standalone menu, for right-clicking the panel and for the "⋯"
// button. This exists because the panel is a .nonactivatingPanel: clicking it never
// makes the app active, and macOS only draws an app's menu bar while it IS active — so
// in normal use the menu bar belongs to whatever app was focused before, and About /
// Support / Help would be unreachable. This menu does not depend on activation at all.
//--------------------------------------------------------------------------------
func buildActionMenu() -> NSMenu {
    func link(_ title: String, _ url: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: #selector(MenuActions.openURL(_:)), keyEquivalent: "")
        entry.target = menuActions
        entry.representedObject = url
        return entry
    }

    let menu = NSMenu()

    let about = NSMenuItem(title: "About Live Clip Envelopes",
                           action: #selector(MenuActions.showAbout(_:)), keyEquivalent: "")
    about.target = menuActions
    menu.addItem(about)
    menu.addItem(.separator())

    let permission = NSMenuItem(title: "Accessibility Permission…",
                                action: #selector(MenuActions.checkPermission(_:)), keyEquivalent: "")
    permission.target = menuActions
    menu.addItem(permission)

    let setup = NSMenuItem(title: "Check Setup…",
                           action: #selector(MenuActions.checkSetup(_:)), keyEquivalent: "")
    setup.target = menuActions
    menu.addItem(setup)
    menu.addItem(.separator())

    let support = NSMenuItem(title: "Support Esa", action: nil, keyEquivalent: "")
    let supportSub = NSMenu()
    for (name, url) in SUPPORT_LINKS { supportSub.addItem(link(name, url)) }
    supportSub.addItem(.separator())
    supportSub.addItem(link("Rate / share on Gumroad", STORE_URL))
    support.submenu = supportSub
    menu.addItem(support)

    let help = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
    let helpSub = NSMenu()
    helpSub.addItem(link("Live Clip Envelopes Help (README)", HELP_URL))
    helpSub.addItem(link("Report an Issue", HELP_URL + "/issues"))
    helpSub.addItem(.separator())
    helpSub.addItem(link("AbletonOSC (required)", "https://github.com/ideoforms/AbletonOSC"))
    help.submenu = helpSub
    menu.addItem(help)

    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit Live Clip Envelopes",
                          action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    menu.addItem(quit)
    return menu
}

func buildMainMenu() -> NSMenu {
    func item(_ title: String, _ url: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: #selector(MenuActions.openURL(_:)), keyEquivalent: "")
        entry.target = menuActions
        entry.representedObject = url
        return entry
    }

    let main = NSMenu()

    // --- application menu -------------------------------------------------------
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    let about = NSMenuItem(title: "About Live Clip Envelopes",
                           action: #selector(MenuActions.showAbout(_:)), keyEquivalent: "")
    about.target = menuActions
    appMenu.addItem(about)
    appMenu.addItem(.separator())

    let permission = NSMenuItem(title: "Accessibility Permission…",
                                action: #selector(MenuActions.checkPermission(_:)), keyEquivalent: "")
    permission.target = menuActions
    appMenu.addItem(permission)

    let setup = NSMenuItem(title: "Check Setup…",
                           action: #selector(MenuActions.checkSetup(_:)), keyEquivalent: "")
    setup.target = menuActions
    appMenu.addItem(setup)
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide Live Clip Envelopes",
                    action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(withTitle: "Quit Live Clip Envelopes",
                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    main.addItem(appItem)

    // --- Support ---------------------------------------------------------------
    let supportItem = NSMenuItem()
    let supportMenu = NSMenu(title: "Support")
    for (name, url) in SUPPORT_LINKS { supportMenu.addItem(item(name, url)) }
    supportMenu.addItem(.separator())
    supportMenu.addItem(item("Rate / share on Gumroad", STORE_URL))
    supportItem.submenu = supportMenu
    supportItem.title = "Support"
    main.addItem(supportItem)

    // --- Help -------------------------------------------------------------------
    let helpItem = NSMenuItem()
    let helpMenu = NSMenu(title: "Help")
    helpMenu.addItem(item("Live Clip Envelopes Help (README)", HELP_URL))
    helpMenu.addItem(item("Report an Issue", HELP_URL + "/issues"))
    helpMenu.addItem(.separator())
    helpMenu.addItem(item("AbletonOSC (required)", "https://github.com/ideoforms/AbletonOSC"))
    helpItem.submenu = helpMenu
    helpItem.title = "Help"
    main.addItem(helpItem)
    // Gives it the magnifying-glass help search and the standard Help placement.
    NSApp.helpMenu = helpMenu

    return main
}

let app = NSApplication.shared
//--------------------------------------------------------------------------------
// Regular, not accessory: this needs a Dock icon so it can be launched from the
// Dock like any other app, at the cost of taking a normal spot in Cmd-Tab.
//--------------------------------------------------------------------------------
app.setActivationPolicy(.regular)
app.mainMenu = buildMainMenu()

let delegate = AppDelegate()
app.delegate = delegate
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: PanelController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = PanelController()
        panelController = controller
    }
    //--------------------------------------------------------------------------------
    // MUST be false. AppKit does not count a .utilityWindow NSPanel as a window for the
    // "last window closed" test, so with `true` here the app decided its last window had
    // gone and quit itself as soon as ANY transient window closed — the About panel, or
    // the popped-up ⋯ menu. That is why choosing About, or opening a Support link, made
    // the app vanish. Quitting is now only ever explicit: the Quit item, or closing the
    // panel (see windowWillClose below).
    //--------------------------------------------------------------------------------
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
// rebuild-test-1786225286
