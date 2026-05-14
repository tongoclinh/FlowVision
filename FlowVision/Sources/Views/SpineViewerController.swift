//
//  SpineViewerController.swift
//  FlowVision
//

import AppKit
import MetalKit

class SpineViewerController: NSViewController {

    private let folderURL: URL
    private var spineView: SpineUIView?
    private(set) var spineController: SpineController?
    private var controlsBar: SpineControlsBar?
    private var interactionView: SpineInteractionView?
    private var updateTimer: Timer?
    private var isLooping = true

    private(set) var availableAnimations: [String] = []
    private(set) var availableSkins: [String] = []

    init(folderURL: URL) {
        self.folderURL = folderURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        let iv = SpineInteractionView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.topAnchor.constraint(equalTo: view.topAnchor),
            iv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            iv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        interactionView = iv
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSpineModel()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(interactionView)
    }

    private func loadSpineModel() {
        guard MTLCreateSystemDefaultDevice() != nil else {
            showError("Metal is not available on this system")
            return
        }

        let spineFiles = SpineDetector.findSpineFiles(in: folderURL)
        guard let model = spineFiles.first else {
            showError("Invalid Spine model: missing skeleton or atlas file\nin \(folderURL.path)")
            return
        }
        let skelURL = model.skeleton
        let atlasURL = model.atlas

        let controller = SpineController(onInitialized: { [weak self] ctrl in
            DispatchQueue.main.async {
                guard let self else { return }
                self.availableAnimations = ctrl.skeletonData.animations.compactMap { $0.name }
                self.availableSkins = ctrl.skeletonData.skins.compactMap { $0.name }
                if let first = self.availableAnimations.first {
                    ctrl.animationState.setAnimationByName(
                        trackIndex: 0, animationName: first, loop: true
                    )
                }
                self.setupControls(selectedAnimation: self.availableAnimations.first)
            }
        })

        self.spineController = controller

        Task.detached(priority: .high) { [weak self] in
            guard let self else { return }
            do {
                let source = SpineViewSource.file(atlasFile: atlasURL, skeletonFile: skelURL)
                let drawable = try await source.loadDrawable()
                await MainActor.run {
                    guard self.view.window != nil else { return }
                    let container = self.interactionView ?? self.view
                    let sv = SpineUIView(
                        from: .drawable(drawable),
                        controller: controller,
                        mode: .fit,
                        alignment: .center,
                        boundsProvider: SetupPoseBounds(),
                        backgroundColor: .black
                    )
                    sv.frame = container.bounds
                    sv.autoresizingMask = [.width, .height]
                    container.addSubview(sv)
                    self.interactionView?.setTarget(sv)
                    self.spineView = sv
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.showError("Failed to load Spine model:\n\(error)\n\nFile: \(skelURL.lastPathComponent)\nAtlas: \(atlasURL.lastPathComponent)")
                }
            }
        }
    }

    private func setupControls(selectedAnimation: String?) {
        let bar = SpineControlsBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        bar.setAnimations(availableAnimations, selected: selectedAnimation)
        bar.setSkins(availableSkins)

        bar.onPlayPause = { [weak self] in
            guard let ctrl = self?.spineController else { return }
            if ctrl.isPlaying { ctrl.pause() } else { ctrl.resume() }
            self?.controlsBar?.updatePlayState(ctrl.isPlaying)
        }
        bar.onSelectAnimation = { [weak self] name in
            guard let self else { return }
            self.spineController?.animationState.setAnimationByName(
                trackIndex: 0, animationName: name, loop: self.isLooping
            )
        }
        bar.onSelectSkin = { [weak self] name in
            self?.spineController?.skeleton.setSkinByName(skinName: name)
            self?.spineController?.skeleton.setToSetupPose()
        }
        bar.onChangeSpeed = { [weak self] speed in
            self?.spineController?.animationState.timeScale = speed
        }
        bar.onToggleLoop = { [weak self] loop in
            self?.isLooping = loop
            if let entry = self?.spineController?.animationState.getCurrent(trackIndex: 0) {
                entry.loop = loop
            }
        }
        bar.onChangeBgColor = { [weak self] color in
            guard let rgb = color.usingColorSpace(.sRGB) else { return }
            self?.spineView?.clearColor = MTLClearColor(
                red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                blue: Double(rgb.blueComponent), alpha: 1.0
            )
            self?.view.layer?.backgroundColor = color.cgColor
        }

        self.controlsBar = bar

        interactionView?.onPrevAnimation = { [weak self] in
            self?.controlsBar?.selectAdjacentAnimation(next: false)
        }
        interactionView?.onNextAnimation = { [weak self] in
            self?.controlsBar?.selectAdjacentAnimation(next: true)
        }

        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/15, repeats: true) { [weak self] _ in
            guard let self, let entry = self.spineController?.animationState.getCurrent(trackIndex: 0)
            else { return }
            let duration = entry.animation.duration
            let current = (entry.isComplete && !entry.loop) ? duration
                : (duration > 0 ? entry.trackTime.truncatingRemainder(dividingBy: duration) : 0)
            self.controlsBar?.updateTime(current: current, duration: duration)
        }
    }

    private func showError(_ message: String) {
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

    func cleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
        spineView?.isPaused = true
        spineView?.removeFromSuperview()
        spineView = nil
        controlsBar?.removeFromSuperview()
        controlsBar = nil
        interactionView?.removeFromSuperview()
        interactionView = nil
        spineController = nil
    }

    deinit {
        cleanup()
    }
}
