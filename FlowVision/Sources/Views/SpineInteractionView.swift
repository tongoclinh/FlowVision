//
//  SpineInteractionView.swift
//  FlowVision
//

import AppKit
import MetalKit

class SpineInteractionView: NSView {

    var onPrevAnimation: (() -> Void)?
    var onNextAnimation: (() -> Void)?

    private var currentScale: CGFloat = 1.0
    private var skeletonCenter: CGPoint = .zero
    private weak var targetView: MTKView?
    private var originalBounds: CGRect = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func setTarget(_ view: MTKView) {
        targetView = view
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    // MARK: - Mouse

    override func scrollWheel(with event: NSEvent) {
        let factor: CGFloat = 1.0 + event.deltaY * 0.03
        zoom(by: factor, around: convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1.0 + event.magnification, around: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard ensureOriginalBounds() else { return }
        let visibleW = originalBounds.width / currentScale
        let visibleH = originalBounds.height / currentScale
        skeletonCenter.x -= event.deltaX / bounds.width * visibleW
        skeletonCenter.y -= event.deltaY / bounds.height * visibleH
        updateProjection()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { resetTransform() }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
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
        if originalBounds == .zero, let sv = targetView as? SpineUIView, sv.computedBounds != .zero {
            originalBounds = sv.computedBounds
            skeletonCenter = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        }
        return originalBounds != .zero
    }

    private func zoom(by factor: CGFloat, around point: CGPoint) {
        guard ensureOriginalBounds() else { return }
        let newScale = min(max(currentScale * factor, 0.1), 100.0)
        let f = newScale / currentScale

        let visibleW = originalBounds.width / currentScale
        let visibleH = originalBounds.height / currentScale
        let nvx = (point.x - bounds.midX) / bounds.width
        let nvy = (point.y - bounds.midY) / bounds.height

        skeletonCenter.x += nvx * visibleW * (1 - 1 / f)
        skeletonCenter.y -= nvy * visibleH * (1 - 1 / f)

        currentScale = newScale
        updateProjection()
    }

    private func updateProjection() {
        guard let sv = targetView as? SpineUIView else { return }
        let visibleW = originalBounds.width / currentScale
        let visibleH = originalBounds.height / currentScale
        sv.computedBounds = CGRect(
            x: skeletonCenter.x - visibleW / 2,
            y: skeletonCenter.y - visibleH / 2,
            width: visibleW,
            height: visibleH
        )
        sv.delegate?.mtkView(sv, drawableSizeWillChange: sv.drawableSize)
    }

    func resetTransform() {
        guard originalBounds != .zero else { return }
        currentScale = 1.0
        skeletonCenter = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        targetView?.layer?.setAffineTransform(.identity)
        updateProjection()
    }
}
