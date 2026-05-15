//
//  SpineUIViewModelViewerConformance.swift
//  FlowVision
//

import MetalKit

extension SpineUIView: ModelViewer {
    var viewerView: MTKView { self }
    var isYAxisFlipped: Bool { true }

    func setProjection(visibleBounds: CGRect) {
        computedBounds = visibleBounds
        delegate?.mtkView(self, drawableSizeWillChange: drawableSize)
    }

    func originalBounds() -> CGRect {
        computedBounds
    }
}
