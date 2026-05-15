//
//  ModelInteractionView.swift
//  FlowVision
//

import AppKit
import MetalKit

class ModelInteractionView: NSView {

    var onPrevAnimation: (() -> Void)?
    var onNextAnimation: (() -> Void)?
    var onScaleChanged: ((CGFloat) -> Void)?
    var additionalViewers: [any ModelViewer] = []

    private(set) var currentScale: CGFloat = 1.0
    private(set) var skeletonCenter: CGPoint = .zero
    private weak var targetViewer: (any ModelViewer)?
    private var cachedOriginalBounds: CGRect = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func setTarget(_ viewer: any ModelViewer) {
        targetViewer = viewer
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    // MARK: - Mouse

    override func scrollWheel(with event: NSEvent) {
        log("[NAV-DBG] ModelInteractionView.scrollWheel captured (deltaY=\(event.deltaY))")
        let factor: CGFloat = 1.0 + event.deltaY * 0.03
        zoom(by: factor, around: convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1.0 + event.magnification, around: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard ensureOriginalBounds() else { return }
        let visibleW = cachedOriginalBounds.width / currentScale
        let visibleH = cachedOriginalBounds.height / currentScale
        let ySign: CGFloat = (targetViewer?.isYAxisFlipped ?? true) ? -1 : 1
        skeletonCenter.x -= event.deltaX / bounds.width * visibleW
        skeletonCenter.y += ySign * event.deltaY / bounds.height * visibleH
        updateProjection()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { resetTransform() }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        log("[NAV-DBG] ModelInteractionView.keyDown: '\(event.charactersIgnoringModifiers ?? "")' isHidden=\(isHidden)")
        switch event.charactersIgnoringModifiers {
        case "+", "=": zoom(by: 1.25, around: CGPoint(x: bounds.midX, y: bounds.midY))
        case "-": zoom(by: 0.8, around: CGPoint(x: bounds.midX, y: bounds.midY))
        case "0": resetTransform()
        case "[": onPrevAnimation?()
        case "]": onNextAnimation?()
        default: super.keyDown(with: event)
        }
    }

    // MARK: - Projection Zoom

    @discardableResult
    private func ensureOriginalBounds() -> Bool {
        if cachedOriginalBounds == .zero {
            let bounds = targetViewer?.originalBounds() ?? .zero
            if bounds != .zero {
                cachedOriginalBounds = bounds
                skeletonCenter = CGPoint(x: bounds.midX, y: bounds.midY)
            }
        }
        return cachedOriginalBounds != .zero
    }

    private func zoom(by factor: CGFloat, around point: CGPoint) {
        guard ensureOriginalBounds() else { return }
        let newScale = min(max(currentScale * factor, 0.1), 100.0)
        let f = newScale / currentScale

        let visibleW = cachedOriginalBounds.width / currentScale
        let visibleH = cachedOriginalBounds.height / currentScale
        let nvx = (point.x - bounds.midX) / bounds.width
        let nvy = (point.y - bounds.midY) / bounds.height

        let ySign: CGFloat = (targetViewer?.isYAxisFlipped ?? true) ? -1 : 1
        skeletonCenter.x += nvx * visibleW * (1 - 1 / f)
        skeletonCenter.y += ySign * nvy * visibleH * (1 - 1 / f)

        currentScale = newScale
        updateProjection()
        onScaleChanged?(currentScale)
    }

    private func updateProjection() {
        let visibleW = cachedOriginalBounds.width / currentScale
        let visibleH = cachedOriginalBounds.height / currentScale
        let bounds = CGRect(
            x: skeletonCenter.x - visibleW / 2,
            y: skeletonCenter.y - visibleH / 2,
            width: visibleW,
            height: visibleH
        )
        targetViewer?.setProjection(visibleBounds: bounds)
        for viewer in additionalViewers {
            viewer.setProjection(visibleBounds: bounds)
        }
    }

    func restoreState(scale: CGFloat, center: CGPoint) {
        guard ensureOriginalBounds() else { return }
        currentScale = min(max(scale, 0.1), 100.0)
        skeletonCenter = center
        updateProjection()
        onScaleChanged?(currentScale)
    }

    func resetTransform() {
        guard cachedOriginalBounds != .zero else { return }
        currentScale = 1.0
        skeletonCenter = CGPoint(x: cachedOriginalBounds.midX, y: cachedOriginalBounds.midY)
        targetViewer?.viewerView.layer?.setAffineTransform(.identity)
        for viewer in additionalViewers {
            viewer.viewerView.layer?.setAffineTransform(.identity)
        }
        updateProjection()
        onScaleChanged?(currentScale)
    }
}
