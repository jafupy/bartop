import AppKit
import SwiftUI

// Let the hosted content determine its size; the menu supplies the material.
final class NativeDashboardMenu: NSMenu {
    private let hosting: DashboardMenuHostingView
    private let dashboardItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var refreshing = false

    init(rootView: Dashboard) {
        hosting = DashboardMenuHostingView(rootView: rootView)
        super.init(title: "bartop")
        autoenablesItems = false
        dashboardItem.isEnabled = true
        dashboardItem.view = hosting
        addItem(dashboardItem)
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.onLayoutChange = { [weak self] in self?.refreshLayout() }
        refreshLayout()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshLayout() {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let naturalSize = hosting.fittingSize
        guard hosting.frame.size != naturalSize else { return }
        hosting.setFrameSize(naturalSize)
        hosting.layoutSubtreeIfNeeded()
        itemChanged(dashboardItem)
        update()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode != 53,
           let editor = hosting.window?.firstResponder as? NSTextView,
           editor.isFieldEditor {
            editor.keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class DashboardMenuHostingView: NSHostingView<Dashboard> {
    var onLayoutChange: (() -> Void)?

    override var allowsVibrancy: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        onLayoutChange?()
    }
}
