//
//  SpineViewerController.swift
//  FlowVision
//

import AppKit
import MetalKit

class SpineViewerController: ModelViewerController {

    private var spineView: SpineUIView?
    private(set) var spineController: SpineController?
    private var updateTimer: Timer?
    private var isLooping = true

    private(set) var availableAnimations: [String] = []
    private(set) var availableSkins: [String] = []

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
                guard let self else { return }
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
                    self.spineView = sv
                    self.modelViewer = sv
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.showError("Failed to load Spine model:\n\(error)\n\nFile: \(skelURL.lastPathComponent)\nAtlas: \(atlasURL.lastPathComponent)")
                }
            }
        }
    }

    private func setupSpineControls(selectedAnimation: String?) {
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

        // Spine-specific: skin picker
        let skinControls = buildSkinControls()
        bar.additionalControlsView = skinControls

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

    private func buildSkinControls() -> NSView {
        let skinLabel = NSTextField(labelWithString: "Skin:")
        skinLabel.font = .systemFont(ofSize: 11)
        skinLabel.textColor = .secondaryLabelColor

        let skinPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        skinPopup.controlSize = .small
        skinPopup.font = .systemFont(ofSize: 11)
        skinPopup.target = self
        skinPopup.action = #selector(skinChanged(_:))
        availableSkins.forEach { skinPopup.addItem(withTitle: $0) }

        let hide = availableSkins.count <= 1
        skinLabel.isHidden = hide
        skinPopup.isHidden = hide

        let separator = controlsBar?.makeVerticalSeparator() ?? NSView()
        separator.isHidden = hide

        let stack = NSStackView(views: [separator, skinLabel, skinPopup])
        stack.orientation = .horizontal
        stack.spacing = 6
        return stack
    }

    @objc private func skinChanged(_ sender: NSPopUpButton) {
        guard let name = sender.titleOfSelectedItem else { return }
        spineController?.skeleton.setSkinByName(skinName: name)
        spineController?.skeleton.setToSetupPose()
    }

    override func cleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
        spineView = nil
        spineController = nil
        super.cleanup()
    }
}
