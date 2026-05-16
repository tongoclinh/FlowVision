//
//  CubismUIView.swift
//  FlowVision
//

import AppKit
import MetalKit

final class CubismUIView: MTKView, ModelViewer {

    let modelHandle = CubismModelHandle()
    private(set) var commandQueue: MTLCommandQueue?
    var folderURL: URL?
    var modelJsonName: String?

    var animationPaused: Bool = false {
        didSet { super.isPaused = animationPaused }
    }
    var playbackSpeed: Float = 1.0
    var isLookAtEnabled: Bool = true
    var isPhysicsEnabled: Bool = true {
        didSet { modelHandle.setPhysicsEnabled(isPhysicsEnabled) }
    }

    var viewerView: MTKView { self }
    var isYAxisFlipped: Bool { false }

    private var lastRenderedTexture: MTLTexture?

    init() {
        let device = MTLCreateSystemDefaultDevice()!
        super.init(frame: .zero, device: device)
        commandQueue = device.makeCommandQueue()
        delegate = self
        preferredFramesPerSecond = 60
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        clearColor = MTLClearColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
        layer?.isOpaque = true
        framebufferOnly = false
    }

    func captureSnapshot(maxSize: CGFloat) -> CGImage? {
        guard let texture = lastRenderedTexture else { return nil }
        return ModelSnapshot.cgImage(from: texture, maxSize: maxSize)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    // MARK: - Zoom/Pan state

    private var currentScale: CGFloat = 1.0
    private var viewCenter: CGPoint = .zero
    private var cachedOriginalBounds: CGRect = .zero

    override func scrollWheel(with event: NSEvent) {
        let factor: CGFloat = 1.0 + event.deltaY * 0.03
        zoomView(by: factor, around: convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        zoomView(by: 1.0 + event.magnification, around: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard ensureOrigBounds() else { return }
        let visibleW = cachedOriginalBounds.width / currentScale
        let visibleH = cachedOriginalBounds.height / currentScale
        viewCenter.x -= event.deltaX / bounds.width * visibleW
        viewCenter.y -= event.deltaY / bounds.height * visibleH
        applyProjection()
    }

    private func ensureOrigBounds() -> Bool {
        if cachedOriginalBounds == .zero {
            let ob = originalBounds()
            if ob != .zero {
                cachedOriginalBounds = ob
                viewCenter = CGPoint(x: ob.midX, y: ob.midY)
            }
        }
        return cachedOriginalBounds != .zero
    }

    private func zoomView(by factor: CGFloat, around point: CGPoint) {
        guard ensureOrigBounds() else { return }
        let newScale = min(max(currentScale * factor, 0.1), 100.0)
        let f = newScale / currentScale
        let visibleW = cachedOriginalBounds.width / currentScale
        let visibleH = cachedOriginalBounds.height / currentScale
        let nvx = (point.x - bounds.midX) / bounds.width
        let nvy = (point.y - bounds.midY) / bounds.height
        viewCenter.x += nvx * visibleW * (1 - 1 / f)
        viewCenter.y -= nvy * visibleH * (1 - 1 / f)
        currentScale = newScale
        applyProjection()
    }

    private func applyProjection() {
        let visibleW = cachedOriginalBounds.width / currentScale
        let visibleH = cachedOriginalBounds.height / currentScale
        setProjection(visibleBounds: CGRect(
            x: viewCenter.x - visibleW / 2,
            y: viewCenter.y - visibleH / 2,
            width: visibleW,
            height: visibleH
        ))
    }

    func resetZoom() {
        guard cachedOriginalBounds != .zero else { return }
        currentScale = 1.0
        viewCenter = CGPoint(x: cachedOriginalBounds.midX, y: cachedOriginalBounds.midY)
        modelHandle.resetViewBounds()
    }

    func loadModel(from folderURL: URL, modelFiles: CubismModelFiles? = nil) -> Bool {
        self.folderURL = folderURL
        let target: CubismModelFiles
        if let modelFiles {
            target = modelFiles
        } else {
            guard let first = CubismDetector.findModelFiles(in: folderURL).first else { return false }
            target = first
        }

        modelJsonName = target.modelJson.lastPathComponent

        guard let device = device, let commandQueue = commandQueue else { return false }
        CubismEngine.start(with: device)

        let size = bounds.size.width > 0 ? bounds.size : CGSize(width: 800, height: 600)
        let ok = modelHandle.load(
            fromPath: folderURL.path,
            jsonFileName: modelJsonName!,
            width: Float(size.width),
            height: Float(size.height),
            device: device,
            commandQueue: commandQueue
        )
        if ok { buildMotionList() }
        return ok
    }

    func setProjection(visibleBounds: CGRect) {
        let left = Float(visibleBounds.minX)
        let right = Float(visibleBounds.maxX)
        let bottom = Float(visibleBounds.minY)
        let top = Float(visibleBounds.maxY)
        modelHandle.setViewBounds(left, right: right, bottom: bottom, top: top)
    }

    func originalBounds() -> CGRect {
        let cw = CGFloat(modelHandle.canvasWidth)
        let ch = CGFloat(modelHandle.canvasHeight)
        let viewW = bounds.width
        let viewH = bounds.height
        guard cw > 0, ch > 0, viewW > 0, viewH > 0 else {
            return CGRect(x: -1, y: -1, width: 2, height: 2)
        }
        let canvasRatio = ch / cw
        let displayRatio = viewH / viewW
        let aspectRatio = viewW / viewH
        if canvasRatio < displayRatio {
            return CGRect(x: -1, y: -1 / aspectRatio, width: 2, height: 2 / aspectRatio)
        } else {
            return CGRect(x: -aspectRatio, y: -1, width: 2 * aspectRatio, height: 2)
        }
    }

    // MARK: - Animation info

    struct MotionInfo {
        let group: String
        let index: Int
        let displayName: String
    }

    private(set) var motionList: [MotionInfo] = []

    var animationNames: [String] {
        motionList.map(\.displayName)
    }

    func buildMotionList() {
        var list = [MotionInfo]()
        let groupCount = modelHandle.motionGroupCount
        for g in 0..<groupCount {
            let groupName = modelHandle.motionGroupName(at: g)
            let count = modelHandle.motionCount(inGroup: groupName)
            for m in 0..<count {
                let fileName = modelHandle.motionFileName(inGroup: groupName, at: m)
                var short = fileName
                if let lastSlash = short.lastIndex(of: "/") {
                    short = String(short[short.index(after: lastSlash)...])
                }
                if short.hasSuffix(".motion3.json") {
                    short = String(short.dropLast(".motion3.json".count))
                }
                let display = groupName.isEmpty ? short : "\(groupName)/\(short)"
                list.append(MotionInfo(group: groupName, index: m, displayName: display))
            }
        }
        motionList = list
    }

    func startMotion(byName name: String, priority: Int = 3) {
        guard let info = motionList.first(where: { $0.displayName == name }) else { return }
        modelHandle.startMotion(inGroup: info.group, at: info.index, priority: priority)
    }

    func startMotion(group: String, index: Int, priority: Int = 2) {
        modelHandle.startMotion(inGroup: group, at: index, priority: priority)
    }

    // MARK: - Expression info

    var expressionNames: [String] {
        var names = [String]()
        let count = modelHandle.expressionCount
        for i in 0..<count {
            names.append(modelHandle.expressionName(at: i))
        }
        return names
    }

    func setExpression(_ name: String) {
        modelHandle.setExpression(name)
    }

    // MARK: - Interaction

    func setDrag(x: Float, y: Float) {
        modelHandle.setDragX(x, y: y)
    }

    func setPhysicsEnabled(_ enabled: Bool) {
        modelHandle.setPhysicsEnabled(enabled)
    }

    func hitTestModel(at x: Float, y: Float) -> String? {
        return modelHandle.hitTestAt(x: x, y: y)
    }

    // MARK: - Cleanup

    func dispose() {
        modelHandle.dispose()
    }
}

// MARK: - MTKViewDelegate

extension CubismUIView: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !animationPaused else { return }
        guard let device = view.device,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderPassDesc = view.currentRenderPassDescriptor else { return }

        CubismEngine.updateTime()
        CubismEngine.beginFrame(with: device)

        modelHandle.update(withSpeed: playbackSpeed)

        let viewport = MTLViewport(
            originX: 0, originY: 0,
            width: Double(view.drawableSize.width),
            height: Double(view.drawableSize.height),
            znear: 0, zfar: 1
        )

        modelHandle.draw(
            with: commandBuffer,
            renderPassDesc: renderPassDesc,
            viewport: viewport
        )

        if let drawable = view.currentDrawable {
            // Keep a strong ref to the texture so captureSnapshot can read it after the frame.
            lastRenderedTexture = drawable.texture
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()

        CubismEngine.endFrame(with: device)
    }
}
