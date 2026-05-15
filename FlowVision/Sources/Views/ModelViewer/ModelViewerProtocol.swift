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
}
