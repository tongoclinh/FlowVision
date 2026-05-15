//
//  CheckerPatternView.swift
//  FlowVision
//

import AppKit

enum CheckerVariant {
    case dark
    case light

    var colors: (NSColor, NSColor) {
        switch self {
        case .dark:
            return (NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1),
                    NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1))
        case .light:
            return (NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
                    NSColor(red: 0.878, green: 0.878, blue: 0.878, alpha: 1))
        }
    }
}

enum BackgroundMode {
    case solid(NSColor)
    case checker(CheckerVariant)

    private static let defaultsKey = "modelViewerBgMode"
    private static let bgColorKey = "modelViewerBgColor"

    func save() {
        let defaults = UserDefaults.standard
        switch self {
        case .solid(let color):
            defaults.set("solid", forKey: Self.defaultsKey)
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) {
                defaults.set(data, forKey: Self.bgColorKey)
            }
        case .checker(let variant):
            defaults.set(variant == .dark ? "checkerDark" : "checkerLight", forKey: Self.defaultsKey)
        }
    }

    static func loadSaved() -> BackgroundMode {
        let defaults = UserDefaults.standard
        guard let mode = defaults.string(forKey: defaultsKey) else { return .solid(.black) }
        switch mode {
        case "checkerDark": return .checker(.dark)
        case "checkerLight": return .checker(.light)
        default:
            if let data = defaults.data(forKey: bgColorKey),
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                return .solid(color)
            }
            return .solid(.black)
        }
    }
}

class CheckerPatternView: NSView {

    var variant: CheckerVariant = .dark {
        didSet { needsDisplay = true }
    }

    private let tileSize: CGFloat = 10

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let (c1, c2) = variant.colors

        c1.setFill()
        ctx.fill(dirtyRect)

        c2.setFill()
        let startCol = Int(floor(dirtyRect.minX / tileSize))
        let endCol = Int(ceil(dirtyRect.maxX / tileSize))
        let startRow = Int(floor(dirtyRect.minY / tileSize))
        let endRow = Int(ceil(dirtyRect.maxY / tileSize))

        for row in startRow..<endRow {
            for col in startCol..<endCol {
                if (row + col) % 2 == 0 { continue }
                let rect = CGRect(x: CGFloat(col) * tileSize,
                                  y: CGFloat(row) * tileSize,
                                  width: tileSize, height: tileSize)
                ctx.fill(rect)
            }
        }
    }
}
