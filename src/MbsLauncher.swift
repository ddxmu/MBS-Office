import AppKit
import Foundation

final class MbsLauncher: NSObject, NSApplicationDelegate {
    private var child: Process?
    private var ready = false
    private var decided = false
    private var pending: [URL] = []
    private var decisionTimer: DispatchWorkItem?
    private let independent = MbsIndependentEditorRouter()

    private var engine: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/MbsEngine.app", isDirectory: true)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        pending.append(contentsOf: filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
        if decided { openPending() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Finder can deliver openFiles immediately after launch. Give that
        // Apple event a short deterministic window before starting the legacy
        // engine, so supported files go directly to the independent editor.
        let work = DispatchWorkItem { [weak self] in self?.decideStartup() }
        decisionTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: work)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if ready {
            NSWorkspace.shared.openApplication(at: engine, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                if let error { self?.fail("Mbs Office 无法显示窗口", error.localizedDescription) }
            }
        }
        return false
    }

    private func decideStartup() {
        guard !decided else { return }
        decided = true
        openPending()
        if pending.isEmpty { startLegacyEngine() }
    }

    private func openPending() {
        guard !pending.isEmpty else { return }
        let urls = pending
        pending.removeAll()
        let fallback = independent.open(urls) { [weak self] reason in
            self?.independent.showActivationPrompt(reason: reason)
        }
        if !fallback.isEmpty {
            pending = fallback
            startLegacyEngine()
        } else if child == nil {
            NSApp.terminate(nil)
        }
    }

    private func startLegacyEngine() {
        guard child == nil, !ready else {
            if ready { openLegacyPending() }
            return
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.mbs.office.wps")
        if running.contains(where: { $0.bundleURL?.standardizedFileURL != engine.standardizedFileURL }) {
            fail("另一个 Mbs Office 测试副本正在运行", "请先保存文档并退出另一个测试副本，再打开此版本。")
            return
        }
        if !running.isEmpty {
            ready = true
            openLegacyPending()
            if pending.isEmpty { running.first?.activate(options: [.activateIgnoringOtherApps]); NSApp.terminate(nil) }
            return
        }
        do {
            let task = Process()
            task.executableURL = engine.appendingPathComponent("Contents/MacOS/wpsoffice")
            task.terminationHandler = { _ in DispatchQueue.main.async { NSApp.terminate(nil) } }
            child = task
            try task.run()
            let deadline = Date().addingTimeInterval(30)
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                if NSRunningApplication(processIdentifier: task.processIdentifier)?.isFinishedLaunching == true {
                    timer.invalidate(); self.ready = true; self.openLegacyPending()
                } else if Date() > deadline {
                    timer.invalidate(); self.fail("Mbs Office 启动尚未完成", "编辑器未能及时完成启动。请检查编辑器窗口或系统提示。")
                }
            }
        } catch { fail("Mbs Office 启动失败", error.localizedDescription) }
    }

    private func openLegacyPending() {
        guard !pending.isEmpty else { return }
        let urls = pending
        pending.removeAll()
        NSWorkspace.shared.open(urls, withApplicationAt: engine, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error { self?.fail("无法打开文档", error.localizedDescription) }
            else if self?.child == nil { NSApp.terminate(nil) }
        }
    }

    private func fail(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
        NSApp.terminate(nil)
    }
}

@main
struct MbsLauncherMain {
    static func main() {
        let app = NSApplication.shared
        let launcher = MbsLauncher()
        app.delegate = launcher
        app.run()
    }
}
