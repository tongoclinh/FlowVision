//
//  ModelViewerController.swift
//  FlowVision
//

import AppKit
import MetalKit

class ModelViewerController: NSViewController {

    let folderURL: URL
    var modelViewer: (any ModelViewer)? {
        didSet {
            if let viewer = modelViewer {
                interactionView?.setTarget(viewer)
            }
        }
    }
    private(set) var interactionView: ModelInteractionView?
    private(set) var controlsBar: ModelControlsBar?
    private(set) var checkerView: CheckerPatternView?

    init(folderURL: URL) {
        self.folderURL = folderURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        let cv = CheckerPatternView()
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.isHidden = true
        view.addSubview(cv)
        checkerView = cv

        let iv = ModelInteractionView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iv)

        NSLayoutConstraint.activate([
            cv.topAnchor.constraint(equalTo: view.topAnchor),
            cv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            iv.topAnchor.constraint(equalTo: view.topAnchor),
            iv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            iv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        interactionView = iv
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(interactionView)
    }

    @discardableResult
    func installControlsBar() -> ModelControlsBar {
        let bar = ModelControlsBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.controlsBar = bar

        interactionView?.onScaleChanged = { [weak bar] scale in
            bar?.updateZoom(scale)
        }

        bar.onChangeBgMode = { [weak self] mode in
            self?.applyBackgroundMode(mode)
        }

        let savedMode = BackgroundMode.loadSaved()
        bar.applyBgMode(savedMode)
        applyBackgroundMode(savedMode, save: false)

        return bar
    }

    func applyBackgroundMode(_ mode: BackgroundMode, save: Bool = true) {
        if save { mode.save() }
        switch mode {
        case .solid(let color):
            checkerView?.isHidden = true
            view.layer?.backgroundColor = color.cgColor
        case .checker(let variant):
            checkerView?.variant = variant
            checkerView?.isHidden = false
            view.layer?.backgroundColor = nil
        }
        modelViewer?.applyBackground(mode)
    }

    func showError(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.textColor = .white
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.isSelectable = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40)
        ])
    }

    // MARK: - State Persistence

    func collectViewerState() -> Encodable? { nil }

    func applyViewerState(from data: Data) {}

    func loadSavedState() {
        guard let data = ModelViewerStateManager.loadData(for: folderURL),
              let state = ModelViewerStateManager.decodeBase(from: data) else { return }

        if let speed = state.playbackSpeed {
            controlsBar?.setSpeed(speed)
            controlsBar?.onChangeSpeed?(speed)
        }

        if let loop = state.isLooping {
            controlsBar?.setLoopState(loop)
            controlsBar?.onToggleLoop?(loop)
        }

        if let anim = state.selectedAnimation {
            controlsBar?.selectAnimationByName(anim)
        }

        if let scale = state.zoomScale, let center = state.panCenter {
            interactionView?.restoreState(scale: CGFloat(scale), center: center.cgPoint)
        }

        applyViewerState(from: data)
    }

    func collectBaseState() -> ModelViewerState {
        var state = ModelViewerState()
        if let iv = interactionView {
            state.zoomScale = iv.currentScale
            state.panCenter = CodablePoint(iv.skeletonCenter)
        }
        if let bar = controlsBar {
            state.selectedAnimation = bar.selectedAnimationName
            state.playbackSpeed = bar.currentSpeed
            state.isLooping = bar.currentLoopState
        }
        return state
    }

    func saveCurrentState() {
        ModelViewerStateManager.save(
            base: collectBaseState(), viewer: collectViewerState(), for: folderURL)
    }

    private var didCleanup = false

    func cleanup() {
        guard !didCleanup else { return }
        didCleanup = true
        saveCurrentState()
        modelViewer?.viewerView.isPaused = true
        modelViewer?.viewerView.removeFromSuperview()
        modelViewer = nil
        controlsBar?.removeFromSuperview()
        controlsBar = nil
        interactionView?.removeFromSuperview()
        interactionView = nil
    }

    deinit {
        cleanup()
    }
}
