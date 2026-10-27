import AppKit
import SwiftUI

// Render the app's own views to files for layout inspection, without a screen capture.
func renderPreview(directory: String) throws {
    _ = NSApplication.shared
    let sampler = Sampler()
    let monitor = Monitor()
    _ = sampler.read(includeProcesses: true)
    // Collect real history; the generated preview never substitutes mock metrics.
    for _ in 0..<10 {
        Thread.sleep(forTimeInterval: 1)
        let sample = sampler.read(includeProcesses: true)
        monitor.metrics = sample
        monitor.cpuHistory.append(sample.cpu)
        monitor.gpuHistory.append(sample.gpu)
        monitor.downloadHistory.append(sample.download)
        monitor.uploadHistory.append(sample.upload)
        monitor.coreHistory = sample.cores.enumerated().map { index, usage in
            let previous = index < monitor.coreHistory.count ? monitor.coreHistory[index] : []
            return previous + [usage]
        }
    }
    let view = NSHostingView(rootView: Dashboard(monitor: monitor, coresExpanded: true).background(Theme.background))
    view.frame = NSRect(origin: .zero, size: view.fittingSize)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("dashboard.png"))
    let menu = MenuGraph.image(cpu: monitor.cpuHistory, gpu: monitor.gpuHistory, paused: false)
    guard let tiff = menu.tiffRepresentation, let menuBitmap = NSBitmapImageRep(data: tiff),
          let menuPNG = menuBitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try menuPNG.write(to: URL(fileURLWithPath: directory).appendingPathComponent("menu-item.png"))
    print("Rendered live dashboard and menu item to \(directory)")
    _ = window
}
