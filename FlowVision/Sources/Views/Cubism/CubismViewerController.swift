//
//  CubismViewerController.swift
//  FlowVision
//

import AppKit
import MetalKit

struct CubismViewerSpecificState: Codable {
    var selectedExpression: String?
    var physicsEnabled: Bool?
    var lookAtEnabled: Bool?
}

class CubismViewerController: ModelViewerController {

    private var cubismView: CubismUIView?
    private var isPlaying = true
    private var isLooping = false
    private var allModels: [CubismModelFiles] = []
    private var updateTimer: Timer?
    private var expressionPopup: NSPopUpButton?
    private var physicsButton: NSButton?
    private var lookAtButton: NSButton?
    private var loadTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        loadCubismModel()
    }

    private func loadCubismModel(at index: Int = 0) {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard MTLCreateSystemDefaultDevice() != nil else {
            showError("Metal is not available on this system")
            return
        }
        let t1 = CFAbsoluteTimeGetCurrent()

        allModels = CubismDetector.findModelFiles(in: folderURL)
        guard !allModels.isEmpty else {
            showError("No Cubism model found in\n\(folderURL.path)")
            return
        }
        let t2 = CFAbsoluteTimeGetCurrent()

        loadTask?.cancel()
        cubismView?.dispose()
        interactionView?.subviews.filter { $0 is MTKView }.forEach { $0.removeFromSuperview() }
        let t3 = CFAbsoluteTimeGetCurrent()

        let cv = CubismUIView()
        let t4 = CFAbsoluteTimeGetCurrent()
        cv.isPaused = true
        cv.frame = interactionView?.bounds ?? view.bounds
        cv.autoresizingMask = [.width, .height]

        let folder = folderURL
        let files = allModels[index]

        log("[NAV-DBG] Cubism: viewDidLoad sync: metal=\(String(format:"%.1f",(t1-t0)*1000)) findFiles=\(String(format:"%.1f",(t2-t1)*1000)) cleanup=\(String(format:"%.1f",(t3-t2)*1000)) initView=\(String(format:"%.1f",(t4-t3)*1000))ms → launching DispatchQueue.global")

        let handle = cv.modelHandle
        let device = cv.device!
        let queue = cv.commandQueue
        let viewSize = cv.bounds.size.width > 0 ? cv.bounds.size : CGSize(width: 800, height: 600)
        let jsonName = files.modelJson.lastPathComponent
        cv.folderURL = folder
        cv.modelJsonName = jsonName

        loadTask = Task { [weak self] in
            let bgDone = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    log("[NAV-DBG] Cubism: loadModel BEGIN isMainThread=\(Thread.isMainThread)")
                    CubismEngine.start(with: device)
                    let ok = handle.load(
                        fromPath: folder.path,
                        jsonFileName: jsonName,
                        width: Float(viewSize.width),
                        height: Float(viewSize.height),
                        device: device,
                        commandQueue: queue!
                    )
                    log("[NAV-DBG] Cubism: loadModel END ok=\(ok)")
                    cont.resume(returning: ok)
                }
            }
            guard !Task.isCancelled, bgDone else {
                await MainActor.run { [weak self] in
                    if !Task.isCancelled { self?.showError("Failed to load Cubism model from\n\(folder.path)") }
                }
                return
            }
            guard let self, self.view.window != nil, !Task.isCancelled else {
                cv.dispose()
                return
            }
            log("[NAV-DBG] Cubism: MainActor setup + onModelReady")
            cv.buildMotionList()
            cv.isHidden = true
            self.interactionView?.addSubview(cv)
            self.cubismView = cv
            self.modelViewer = cv
            self.installControlsBar()
            self.setupCubismControls()
            cv.isHidden = false
            cv.isPaused = false
            self.onModelReady()
        }
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

        bar.onToggleLoop = { [weak self] loop in
            self?.isLooping = loop
            self?.cubismView?.modelHandle.loopingEnabled = loop
        }

        bar.onChangeBgColor = { [weak self] color in
            self?.applyBackgroundMode(.solid(color))
        }
        bar.onScrub = { [weak cv] time in
            cv?.modelHandle.seekMotion(to: time)
        }
        bar.onScrubEnd = { [weak self] in
            guard let self, let cv = self.cubismView else { return }
            if !self.isPlaying {
                cv.animationPaused = true
            }
        }

        interactionView?.onPrevAnimation = { [weak self] in
            self?.controlsBar?.selectAdjacentAnimation(next: false)
        }
        interactionView?.onNextAnimation = { [weak self] in
            self?.controlsBar?.selectAdjacentAnimation(next: true)
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

        loadSavedState()
    }

    // MARK: - Cubism-specific controls

    private func buildCubismControls(cv: CubismUIView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8

        let expressions = cv.expressionNames
        if !expressions.isEmpty {
            let exprBtn = NSPopUpButton(frame: .zero, pullsDown: false)
            exprBtn.addItem(withTitle: "Expression")
            exprBtn.addItems(withTitles: expressions)
            exprBtn.controlSize = .small
            exprBtn.font = NSFont.systemFont(ofSize: 10)
            exprBtn.target = self
            exprBtn.action = #selector(expressionChanged(_:))
            stack.addArrangedSubview(exprBtn)
            self.expressionPopup = exprBtn
        }

        let physBtn = NSButton(checkboxWithTitle: "Physics", target: self, action: #selector(physicsToggled(_:)))
        physBtn.controlSize = .small
        physBtn.font = NSFont.systemFont(ofSize: 10)
        physBtn.state = .on
        stack.addArrangedSubview(physBtn)
        self.physicsButton = physBtn

        let lookBtn = NSButton(checkboxWithTitle: "Look-at", target: self, action: #selector(lookAtToggled(_:)))
        lookBtn.controlSize = .small
        lookBtn.font = NSFont.systemFont(ofSize: 10)
        lookBtn.state = .on
        stack.addArrangedSubview(lookBtn)
        self.lookAtButton = lookBtn

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

    // MARK: - State Persistence

    override func collectViewerState() -> Encodable? {
        CubismViewerSpecificState(
            selectedExpression: expressionPopup.flatMap { $0.indexOfSelectedItem > 0 ? $0.titleOfSelectedItem : nil },
            physicsEnabled: physicsButton?.state == .on,
            lookAtEnabled: lookAtButton?.state == .on
        )
    }

    override func applyViewerState(from data: Data) {
        guard let vs = try? JSONDecoder().decode(CubismViewerSpecificState.self, from: data)
        else { return }

        if let exprName = vs.selectedExpression, let cv = cubismView {
            expressionPopup?.selectItem(withTitle: exprName)
            cv.setExpression(exprName)
        }

        if let physics = vs.physicsEnabled {
            physicsButton?.state = physics ? .on : .off
            cubismView?.isPhysicsEnabled = physics
        }

        if let lookAt = vs.lookAtEnabled {
            lookAtButton?.state = lookAt ? .on : .off
            cubismView?.isLookAtEnabled = lookAt
        }
    }

    // MARK: - Cleanup

    override func cleanup() {
        let t0 = CFAbsoluteTimeGetCurrent()
        loadTask?.cancel()
        loadTask = nil
        updateTimer?.invalidate()
        updateTimer = nil
        let t1 = CFAbsoluteTimeGetCurrent()
        cubismView?.dispose()
        let t2 = CFAbsoluteTimeGetCurrent()
        cubismView = nil
        log("[NAV-DBG] CubismViewerController.cleanup: cancel=\(String(format:"%.1f",(t1-t0)*1000)) dispose=\(String(format:"%.1f",(t2-t1)*1000))ms")
        super.cleanup()
    }
}

