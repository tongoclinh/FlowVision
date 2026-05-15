//
//  ModelViewerProtocol.swift
//  FlowVision
//

import AppKit
import MetalKit

protocol ModelViewer: AnyObject {
    var viewerView: MTKView { get }
    var isYAxisFlipped: Bool { get }
    func setProjection(visibleBounds: CGRect)
    func originalBounds() -> CGRect
    func applyBackground(_ mode: BackgroundMode)
}

extension ModelViewer {
    func applyBackground(_ mode: BackgroundMode) {
        switch mode {
        case .solid(let color):
            let c = color.usingColorSpace(.sRGB) ?? color
            viewerView.clearColor = MTLClearColor(
                red: Double(c.redComponent), green: Double(c.greenComponent),
                blue: Double(c.blueComponent), alpha: 1.0)
            viewerView.layer?.isOpaque = true
        case .checker:
            viewerView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            viewerView.layer?.isOpaque = false
        }
    }
}
