//
//  SpineViewerController.swift
//  FlowVision
//

import AppKit
import MetalKit

enum SpinePMAMode: String, Codable, CaseIterable {
    case auto = "Auto"
    case pma = "PMA"
    case straight = "Straight"
}

struct SpineViewerSpecificState: Codable {
    var selectedSkin: String?
    var pmaMode: SpinePMAMode?
}

class SpineViewerController: ModelViewerController {

    private var spineView: SpineUIView?
    private(set) var spineController: SpineController?
    private var updateTimer: Timer?
    private var isLooping = true
    private var currentPMAMode: SpinePMAMode = .auto
    private var loadTask: Task<Void, Never>?

    private(set) var availableAnimations: [String] = []
    private(set) var availableSkins: [String] = []
    private var skinPopup: NSPopUpButton?
    private var pmaPopup: NSPopUpButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSpineModel()
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
                guard let self, self.view.window != nil, self.spineView != nil else { return }
                self.availableAnimations = ctrl.skeletonData.animations.compactMap { $0.name }
                self.availableSkins = ctrl.skeletonData.skins.compactMap { $0.name }
                if let first = self.availableAnimations.first {
                    ctrl.animationState.setAnimationByName(
                        trackIndex: 0, animationName: first, loop: true
                    )
                }
                self.setupSpineControls(selectedAnimation: self.availableAnimations.first)
            }
        })

        self.spineController = controller

        log("[NAV-DBG] Spine: launching background load")
        loadTask = Task.detached(priority: .high) {
            do {
                let source = SpineViewSource.file(atlasFile: atlasURL, skeletonFile: skelURL)
                log("[NAV-DBG] Spine: loadDrawable BEGIN isMainThread=\(Thread.isMainThread)")
                let drawable = try await source.loadDrawable()
                log("[NAV-DBG] Spine: loadDrawable END cancelled=\(Task.isCancelled)")
                guard !Task.isCancelled else { return }

                // Build renderer on background — for heavy models this is the dominant cost
                // (shader compilation, atlas texture upload, pipeline states).
                let renderer = try SpineRenderer(
                    device: SpineObjects.shared.device,
                    commandQueue: SpineObjects.shared.commandQueue,
                    pixelFormat: .bgra8Unorm,
                    atlasPages: drawable.atlasPages,
                    pma: drawable.atlas.isPma
                )
                log("[NAV-DBG] Spine: renderer built cancelled=\(Task.isCancelled)")
                guard !Task.isCancelled else { return }

                await MainActor.run { [weak self] in
                    guard let self, self.view.window != nil, !Task.isCancelled else { return }
                    log("[NAV-DBG] Spine: MainActor attaching prebuilt renderer")
                    let container = self.interactionView ?? self.view
                    let sv = SpineUIView(
                        controller: controller,
                        mode: .fit,
                        alignment: .center,
                        boundsProvider: SetupPoseBounds(),
                        backgroundColor: .black
                    )
                    sv.attach(prebuiltRenderer: renderer, drawable: drawable)
                    sv.isHidden = true
                    sv.frame = container.bounds
                    sv.autoresizingMask = [.width, .height]
                    container.addSubview(sv)
                    self.spineView = sv
                    self.modelViewer = sv
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.showError("Failed to load Spine model:\n\(error)\n\nFile: \(skelURL.lastPathComponent)\nAtlas: \(atlasURL.lastPathComponent)")
                }
            }
        }
    }

    private func setupSpineControls(selectedAnimation: String?) {
        guard view.window != nil else { return }
        let bar = installControlsBar()
        bar.setAnimations(availableAnimations, selected: selectedAnimation)

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
            self?.applyBackgroundMode(.solid(color))
        }
        bar.onScrub = { [weak self] time in
            guard let entry = self?.spineController?.animationState.getCurrent(trackIndex: 0) else { return }
            entry.trackTime = time
        }

        // Spine-specific: skin picker
        let skinControls = buildSkinControls()
        bar.additionalControlsView = skinControls

        interactionView?.onPrevAnimation = { [weak self] in
            self?.controlsBar?.selectAdjacentAnimation(next: false)
        }
        interactionView?.onNextAnimation = { [weak self] in
            self?.controlsBar?.selectAdjacentAnimation(next: true)
        }

        let timer = Timer(timeInterval: 1.0/15, repeats: true) { [weak self] _ in
            guard let self, let entry = self.spineController?.animationState.getCurrent(trackIndex: 0)
            else { return }
            let duration = entry.animation.duration
            let current = (entry.isComplete && !entry.loop) ? duration
                : (duration > 0 ? entry.trackTime.truncatingRemainder(dividingBy: duration) : 0)
            self.controlsBar?.updateTime(current: current, duration: duration)
        }
        RunLoop.current.add(timer, forMode: .common)
        updateTimer = timer

        loadSavedState()
        spineView?.isHidden = false
        log("[NAV-DBG] Spine: setupSpineControls done → onModelReady")
        onModelReady()
    }

    private func buildSkinControls() -> NSView {
        let skinLabel = NSTextField(labelWithString: "Skin:")
        skinLabel.font = .systemFont(ofSize: 11)
        skinLabel.textColor = .secondaryLabelColor

        let skinBtn = NSPopUpButton(frame: .zero, pullsDown: false)
        skinBtn.controlSize = .small
        skinBtn.font = .systemFont(ofSize: 11)
        skinBtn.target = self
        skinBtn.action = #selector(skinChanged(_:))
        availableSkins.forEach { skinBtn.addItem(withTitle: $0) }
        self.skinPopup = skinBtn

        let hide = availableSkins.count <= 1
        skinLabel.isHidden = hide
        skinBtn.isHidden = hide

        let skinSeparator = controlsBar?.makeVerticalSeparator() ?? NSView()
        skinSeparator.isHidden = hide

        let pmaLabel = NSTextField(labelWithString: "Blend:")
        pmaLabel.font = .systemFont(ofSize: 11)
        pmaLabel.textColor = .secondaryLabelColor

        let pmaBtn = NSPopUpButton(frame: .zero, pullsDown: false)
        pmaBtn.controlSize = .small
        pmaBtn.font = .systemFont(ofSize: 11)
        pmaBtn.target = self
        pmaBtn.action = #selector(pmaChanged(_:))
        SpinePMAMode.allCases.forEach { pmaBtn.addItem(withTitle: $0.rawValue) }
        self.pmaPopup = pmaBtn

        let pmaSeparator = controlsBar?.makeVerticalSeparator() ?? NSView()

        let stack = NSStackView(views: [
            skinSeparator, skinLabel, skinBtn,
            pmaSeparator, pmaLabel, pmaBtn
        ])
        stack.orientation = .horizontal
        stack.spacing = 6
        return stack
    }

    @objc private func skinChanged(_ sender: NSPopUpButton) {
        guard let name = sender.titleOfSelectedItem else { return }
        spineController?.skeleton.setSkinByName(skinName: name)
        spineController?.skeleton.setToSetupPose()
    }

    @objc private func pmaChanged(_ sender: NSPopUpButton) {
        guard let sv = spineView,
              let mode = SpinePMAMode(rawValue: sender.titleOfSelectedItem ?? "") else { return }
        currentPMAMode = mode
        let pma: Bool
        switch mode {
        case .auto: pma = sv.atlasPma
        case .pma: pma = true
        case .straight: pma = false
        }
        do {
            try sv.reloadRenderer(pma: pma)
        } catch {
            log("Failed to reload renderer with PMA mode \(mode.rawValue): \(error)")
        }
    }

    // MARK: - State Persistence

    override func collectViewerState() -> Encodable? {
        SpineViewerSpecificState(
            selectedSkin: skinPopup?.titleOfSelectedItem,
            pmaMode: currentPMAMode
        )
    }

    override func applyViewerState(from data: Data) {
        guard let vs = try? JSONDecoder().decode(SpineViewerSpecificState.self, from: data)
        else { return }

        if let skinName = vs.selectedSkin, availableSkins.contains(skinName) {
            skinPopup?.selectItem(withTitle: skinName)
            spineController?.skeleton.setSkinByName(skinName: skinName)
            spineController?.skeleton.setToSetupPose()
        }

        if let mode = vs.pmaMode {
            pmaPopup?.selectItem(withTitle: mode.rawValue)
            currentPMAMode = mode
            if let sv = spineView {
                let pma: Bool
                switch mode {
                case .auto: pma = sv.atlasPma
                case .pma: pma = true
                case .straight: pma = false
                }
                do { try sv.reloadRenderer(pma: pma) }
                catch { log("Failed to apply saved PMA mode: \(error)") }
            }
        }
    }

    override func cleanup() {
        loadTask?.cancel()
        loadTask = nil
        updateTimer?.invalidate()
        updateTimer = nil
        spineView = nil
        spineController = nil
        super.cleanup()
    }
}
