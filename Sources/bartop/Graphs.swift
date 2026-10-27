import AppKit
import CoreText
import SwiftUI

enum Theme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let muted = Color.secondary
    static let cpu = Color.primary
    static let gpu = Color.primary
    static let memory = Color.primary
    static let disk = Color.primary
}

enum BrailleGraph {
    static func lines(_ history: [Double?], columns: Int, rows: Int,
                      maximum: Double = 100, inverted: Bool = false) -> [String] {
        let samples = Array(history.suffix(columns))
        let padded = Array<Double?>(repeating: nil, count: columns - samples.count) + samples
        let bits = [[0, 1, 2, 6], [3, 4, 5, 7]]
        let dotRows = rows * 4
        return (0..<rows).map { line in
            (0..<columns / 2).map { cell in
                var mask = 0
                for column in 0..<2 {
                    guard let value = padded[cell * 2 + column] else { continue }
                    let levels = max(0, min(dotRows, Int(ceil(value / maximum * Double(dotRows)))))
                    for row in 0..<4 {
                        let position = line * 4 + row
                        if inverted ? position < levels : position >= dotRows - levels {
                            mask |= 1 << bits[column][row]
                        }
                    }
                }
                return String(UnicodeScalar(0x2800 + mask)!)
            }.joined()
        }
    }
}

private struct BrailleGeometry {
    static let graph = BrailleGeometry(size: 13)
    static let meter = BrailleGeometry(size: 11)
    static let core = BrailleGeometry(size: 10)

    let size: CGFloat
    let cellWidth: CGFloat
    let bearing: CGFloat
    let kerning: CGFloat

    init(size: CGFloat) {
        self.size = size
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        func line(_ string: String) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]) as CFAttributedString)
        }
        let full = line("⣿")
        let fullBounds = CTLineGetImageBounds(full, nil)
        let leftBounds = CTLineGetImageBounds(line("⡇"), nil)
        let advance = CGFloat(CTLineGetTypographicBounds(full, nil, nil, nil))
        // Two dot-column pitches per character, with no extra gap at its boundary.
        cellWidth = max(1, 2 * (fullBounds.width - leftBounds.width))
        bearing = fullBounds.minX
        kerning = cellWidth - advance
    }

    func text(_ string: String) -> Text {
        Text(string).font(.system(size: size, weight: .regular, design: .monospaced)).kerning(kerning)
    }
}

struct BrailleRow: View {
    let text: String

    var body: some View {
        BrailleGeometry.core.text(text).fixedSize()
    }
}

// The upper history grows up; the lower history grows down.
struct SplitGraph: View {
    let upper: [Double]
    let lower: [Double?]
    var rows = 3
    var maximum = 100.0
    var upperColor = Theme.cpu
    var lowerColor = Theme.gpu
    var upperLabel: String? = nil
    var lowerLabel: String? = nil

    var body: some View {
        let geometry = BrailleGeometry.graph
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { _ in geometry.text("⣿") }
                }
            }
        }.hidden().frame(maxWidth: .infinity)
        .overlay {
            Canvas { context, size in
                let center = size.height / 2
                let gap = 8.0
                let cells = max(1, Int(size.width / geometry.cellWidth))
                let graphX = size.width - CGFloat(cells) * geometry.cellWidth
                let height = (size.height - gap) / 2
                let rowHeight = height / CGFloat(rows)
                for (history, inverted, origin, color, label) in [
                    (upper.map { Optional($0) }, false, center - gap / 2 - height, upperColor, upperLabel),
                    (lower, true, center + gap / 2, lowerColor, lowerLabel)
                ] {
                    let lines = BrailleGraph.lines(history, columns: cells * 2, rows: rows,
                                                  maximum: maximum, inverted: inverted)
                    let labelRow = inverted ? rows - 1 : 0
                    let labelText = label.map {
                        context.resolve(Text($0).font(.system(size: 10)).foregroundColor(color))
                    }
                    let labelSize = labelText?.measure(in: CGSize(width: size.width, height: rowHeight))
                    for (line, string) in lines.enumerated() {
                        let hiddenCells = line == labelRow
                            ? labelSize.map { min(cells, Int(ceil(($0.width + 6 - graphX) / geometry.cellWidth))) } ?? 0 : 0
                        let remaining = String(string.dropFirst(hiddenCells))
                        let resolved = context.resolve(geometry.text(remaining).foregroundColor(color))
                        context.draw(resolved,
                                     at: CGPoint(x: graphX + CGFloat(hiddenCells) * geometry.cellWidth - geometry.bearing,
                                                 y: origin + CGFloat(line) * rowHeight), anchor: .topLeading)
                    }
                    if let labelText {
                        context.draw(labelText, at: CGPoint(x: 0, y: origin + (CGFloat(labelRow) + 0.5) * rowHeight),
                                     anchor: .leading)
                    }
                }
            }
        }
        .accessibilityLabel("History graph")
    }
}

struct Meter: View {
    let fraction: Double
    let color: Color
    var body: some View {
        let geometry = BrailleGeometry.meter
        geometry.text("⣿").hidden().frame(maxWidth: .infinity)
        .overlay {
            Canvas { context, size in
                let cells = max(1, Int(size.width / geometry.cellWidth))
                let filledColumns = Int((max(0, min(1, fraction)) * Double(cells * 2)).rounded())
                let samples = (0..<cells * 2).map { Optional($0 < filledColumns ? 100.0 : 0.0) }
                let origin = CGPoint(x: -geometry.bearing, y: 0)
                context.draw(context.resolve(geometry.text(String(repeating: "⣿", count: cells))
                    .foregroundColor(color.opacity(0.16))), at: origin, anchor: .topLeading)
                context.draw(context.resolve(geometry.text(BrailleGraph.lines(samples, columns: cells * 2, rows: 1)[0])
                    .foregroundColor(color)), at: origin, anchor: .topLeading)
            }
        }
    }
}

enum MenuGraph {
    static func image(cpu: [Double], gpu: [Double?], paused: Bool) -> NSImage {
        let size = NSSize(width: 102, height: NSStatusBar.system.thickness)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = rect.height / 2
            let rowHeight = center - 1
            NSColor.labelColor.withAlphaComponent(0.2).setFill()
            NSRect(x: 25, y: center - 0.25, width: 42, height: 0.5).fill()
            for (label, values, inverted, y) in [
                ("CPU", cpu.map { Optional($0) }, false, center + 1),
                ("GPU", gpu, true, 0.0)
            ] {
                let foreground = NSColor.labelColor.withAlphaComponent(paused ? 0.4 : 1)
                let textAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .medium), .foregroundColor: foreground]
                (label as NSString).draw(at: NSPoint(x: 0, y: y + (rowHeight - 10) / 2), withAttributes: textAttributes)
                let graph = BrailleGraph.lines(values, columns: 10, rows: 1, inverted: inverted)[0]
                foreground.setFill()
                // Draw each Unicode braille cell at a larger dot size, keeping four rows
                // within each half of the menu bar. This avoids font fallback clipping.
                let leftBits = [0, 1, 2, 6]
                let rightBits = [3, 4, 5, 7]
                let dotSize = 2.2
                let rowStep = min(2.7, (rowHeight - dotSize - 1) / 3)
                for (index, scalar) in graph.unicodeScalars.enumerated() {
                    let mask = Int(scalar.value) - 0x2800
                    for column in 0..<2 {
                        let bits = column == 0 ? leftBits : rightBits
                        for row in 0..<4 where mask & (1 << bits[row]) != 0 {
                            let x = 26 + Double(index * 2 + column) * 4.2
                            let dotY = y + 0.7 + Double(3 - row) * rowStep
                            NSBezierPath(ovalIn: NSRect(x: x, y: dotY, width: dotSize, height: dotSize)).fill()
                        }
                    }
                }
                let percent = values.last.flatMap { $0 }.map { String(format: "%.0f%%", $0) } ?? "—"
                let width = (percent as NSString).size(withAttributes: textAttributes).width
                (percent as NSString).draw(at: NSPoint(x: rect.width - width, y: y + (rowHeight - 10) / 2), withAttributes: textAttributes)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
