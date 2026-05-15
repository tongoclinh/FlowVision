//
//  CubismViewerController.swift
//  FlowVision
//

import AppKit
import MetalKit

class CubismViewerController: ModelViewerController {

    private var cubismView: CubismUIView?
    private var isPlaying = true
    private var allModels: [CubismModelFiles] = []
    private var updateTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        loadCubismModel()
    }

    private func loadCubismModel(at index: Int = 0) {
        guard MTLCreateSystemDefaultDevice() != nil else {
            showError("Metal is not available on this system")
            return
        }

        allModels = CubismDetector.findModelFiles(in: folderURL)
        guard !allModels.isEmpty else {
            showError("No Cubism model found in\n\(folderURL.path)")
            return
        }

        let cv = CubismUIView()
        cv.frame = view.bounds
        cv.autoresizingMask = [.width, .height]

        let ok = cv.loadModel(from: folderURL, modelFiles: allModels[index])
        guard ok else {
            showError("Failed to load Cubism model from\n\(folderURL.path)")
            return
        }

        cubismView?.dispose()
        cubismView = cv
        self.modelViewer = cv

        interactionView?.subviews.filter { $0 is MTKView }.forEach { $0.removeFromSuperview() }
        interactionView?.addSubview(cv)
        cv.frame = interactionView?.bounds ?? view.bounds

        installControlsBar()
        setupCubismControls()
    }

    private func setupCubismControls() {
        guard let bar = controlsBar, let cv = cubismView else { return }

        let animations = cv.animationNames
        if !animations.isEmpty {
            bar.setAnimations(animations, selected: animations.first)
        }

        bar.onPlayPause = { [weak self] in
            guard let self, let cv = self.cubismView else { return }
            self.isPlaying.toggle()
            cv.animationPaused = !self.isPlaying
            self.controlsBar?.updatePlayState(self.isPlaying)
        }

        bar.onSelectAnimation = { [weak self] name in
            self?.cubismView?.startMotion(byName: name)
        }

        bar.onChangeSpeed = { [weak self] speed in
            self?.cubismView?.playbackSpeed = speed
        }

        bar.onChangeBgColor = { [weak self] color in
            self?.applyBackgroundMode(.solid(color))
        }
        bar.onScrub = { [weak cv] time in
            cv?.modelHandle.seekMotion(to: time)
        }

        bar.additionalControlsView = buildCubismControls(cv: cv)

        let timer = Timer(timeInterval: 1.0/15, repeats: true) { [weak self] _ in
            guard let self, let cv = self.cubismView else { return }
            let current = cv.modelHandle.currentMotionTime
            let duration = cv.modelHandle.currentMotionDuration
            self.controlsBar?.updateTime(current: current, duration: duration)
        }
        RunLoop.current.add(timer, forMode: .common)
        updateTimer = timer
    }

    // MARK: - Cubism-specific controls

    private func buildCubismControls(cv: CubismUIView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8

        let expressions = cv.expressionNames
        if !expressions.isEmpty {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItem(withTitle: "Expression")
            popup.addItems(withTitles: expressions)
            popup.controlSize = .small
            popup.font = NSFont.systemFont(ofSize: 10)
            popup.target = self
            popup.action = #selector(expressionChanged(_:))
            stack.addArrangedSubview(popup)
        }

        let physicsBtn = NSButton(checkboxWithTitle: "Physics", target: self, action: #selector(physicsToggled(_:)))
        physicsBtn.controlSize = .small
        physicsBtn.font = NSFont.systemFont(ofSize: 10)
        physicsBtn.state = .on
        stack.addArrangedSubview(physicsBtn)

        let lookAtBtn = NSButton(checkboxWithTitle: "Look-at", target: self, action: #selector(lookAtToggled(_:)))
        lookAtBtn.controlSize = .small
        lookAtBtn.font = NSFont.systemFont(ofSize: 10)
        lookAtBtn.state = .on
        stack.addArrangedSubview(lookAtBtn)

        if allModels.count > 1 {
            let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            for m in allModels {
                modelPopup.addItem(withTitle: m.modelJson.deletingPathExtension().deletingPathExtension().lastPathComponent)
            }
            modelPopup.controlSize = .small
            modelPopup.font = NSFont.systemFont(ofSize: 10)
            modelPopup.target = self
            modelPopup.action = #selector(modelChanged(_:))
            stack.addArrangedSubview(modelPopup)
        }

        return stack
    }

    @objc private func expressionChanged(_ sender: NSPopUpButton) {
        guard let cv = cubismView, sender.indexOfSelectedItem > 0 else { return }
        let name = sender.titleOfSelectedItem ?? ""
        cv.setExpression(name)
    }

    @objc private func physicsToggled(_ sender: NSButton) {
        cubismView?.isPhysicsEnabled = (sender.state == .on)
    }

    @objc private func lookAtToggled(_ sender: NSButton) {
        cubismView?.isLookAtEnabled = (sender.state == .on)
    }

    @objc private func modelChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < allModels.count else { return }
        loadCubismModel(at: idx)
    }

    // MARK: - Look-at tracking

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.acceptsMouseMovedEvents = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard let cv = cubismView, cv.isLookAtEnabled else {
            super.mouseMoved(with: event)
            return
        }

        let viewPoint = interactionView?.convert(event.locationInWindow, from: nil) ?? .zero
        let viewSize = interactionView?.bounds.size ?? view.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let normalX = Float((viewPoint.x / viewSize.width) * 2.0 - 1.0)
        let normalY = Float((viewPoint.y / viewSize.height) * 2.0 - 1.0)
        cv.setDrag(x: normalX, y: normalY)
    }

    // MARK: - Hit-test

    override func mouseDown(with event: NSEvent) {
        guard let cv = cubismView else {
            super.mouseDown(with: event)
            return
        }

        let viewPoint = interactionView?.convert(event.locationInWindow, from: nil) ?? .zero
        let viewSize = interactionView?.bounds.size ?? view.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let normalX = Float((viewPoint.x / viewSize.width) * 2.0 - 1.0)
        let normalY = Float((viewPoint.y / viewSize.height) * 2.0 - 1.0)

        if let hitArea = cv.hitTestModel(at: normalX, y: normalY) {
            log("Cubism hit area: \(hitArea)")
        }

        super.mouseDown(with: event)
    }

    // MARK: - Cleanup

    override func cleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
        cubismView?.dispose()
        cubismView = nil
        super.cleanup()
    }
}

