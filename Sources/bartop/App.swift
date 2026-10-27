import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = Monitor()
    private var dashboardMenu: NativeDashboardMenu!
    private var statusItem: NSStatusItem!
    private var menuOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 110)
        statusItem.autosaveName = "bartop"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("bartop CPU and GPU monitor")
        }
        dashboardMenu = NativeDashboardMenu(rootView: Dashboard(monitor: monitor))
        dashboardMenu.delegate = self
        monitor.onUpdate = { [weak self] in
            self?.updateMenuItem()
        }
        updateMenuItem()
        monitor.start()
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showDashboard() }
        }
    }

    private func updateMenuItem() {
        let m = monitor.metrics
        statusItem.button?.image = MenuGraph.image(cpu: monitor.cpuHistory, gpu: monitor.gpuHistory, paused: monitor.paused)
        let gpu = m.gpu.map { String(format: "%.0f%%", $0) } ?? "unavailable"
        let description = String(format: "CPU %.0f%% · GPU %@%@", m.cpu, gpu, monitor.paused ? " · paused" : "")
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityValue(description)
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let open = NSMenuItem(title: "Open bartop", action: #selector(showDashboard), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            let pause = NSMenuItem(title: monitor.paused ? "Resume" : "Pause", action: #selector(togglePause), keyEquivalent: "")
            pause.target = self
            menu.addItem(pause)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit bartop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
            menu.addItem(quit)
            show(menu)
        } else {
            showDashboard()
        }
    }

    @objc private func togglePause() { monitor.togglePause() }

    @objc private func showDashboard() {
        guard !menuOpen else { dashboardMenu.cancelTracking(); return }
        dashboardMenu.appearance = NSApp.effectiveAppearance
        dashboardMenu.refreshLayout()
        NSApp.activate(ignoringOtherApps: true)
        show(dashboardMenu)
    }

    private func show(_ menu: NSMenu) {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        monitor.dashboardVisible = true
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        monitor.dashboardVisible = false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !menuOpen { showDashboard() }
        return false
    }
}
