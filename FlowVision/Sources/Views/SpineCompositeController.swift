//
//  SpineCompositeController.swift
//  FlowVision
//

import AppKit
import MetalKit

class SpineCompositeController: ModelViewerController {

    struct SpineLayer {
        let basename: String
        let files: SpineModelFiles
        var spineView: SpineUIView?
        var controller: SpineController?
        var animations: [String] = []
    }

    private let config: CompositeConfig
    private var layers: [SpineLayer] = []
    private var mainLayerIndex: Int = 0
    private var updateTimer: Timer?
    private var isLooping = true
    private var loadedCount = 0
    private var loadTasks: [Task<Void, Never>] = []

    init(folderURL: URL, config: CompositeConfig) {
        self.config = config
        super.init(folderURL: folderURL)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadCompositeLayers()
    }

    private func loadCompositeLayers() {
        guard MTLCreateSystemDefaultDevice() != nil else {
            showError("Metal is not available on this system")
            return
        }

        let allFiles = SpineDetector.findSpineFiles(in: folderURL)
        let filesByBase = Dictionary(
            allFiles.map { ($0.skeleton.deletingPathExtension().lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for basename in config.layers {
            guard let files = filesByBase[basename] else {
                log("Composite layer not found: \(basename)")
                continue
            }
            layers.append(SpineLayer(basename: basename, files: files))
        }

        guard !layers.isEmpty else {
            showError("No valid layers found for composite model")
            return
        }

        mainLayerIndex = layers.firstIndex(where: { $0.basename == config.mainLayer })
            ?? 0

        for i in layers.indices {
            loadLayer(at: i)
        }
    }

    private func loadLayer(at index: Int) {
        let layer = layers[index]
        let isBottom = index == 0
        let bgColor: NSColor = isBottom ? .black : .clear

        let controller = SpineController(onInitialized: { [weak self] ctrl in
            DispatchQueue.main.async {
                guard let self else { return }
                self.layers[index].animations = ctrl.skeletonData.animations.compactMap { $0.name }
                self.layers[index].controller = ctrl

                if let first = self.layers[index].animations.first {
                    ctrl.animationState.setAnimationByName(
                        trackIndex: 0, animationName: first, loop: true)
                }

                self.loadedCount += 1
                if self.loadedCount == self.layers.count {
                    self.onAllLayersLoaded()
                }
            }
        })

        let atlasURL = layer.files.atlas
        let skelURL = layer.files.skeleton
        let basename = layer.basename

        let task = Task.detached(priority: .high) {
            do {
                let source = SpineViewSource.file(
                    atlasFile: atlasURL, skeletonFile: skelURL)
                let drawable = try await source.loadDrawable()
                guard !Task.isCancelled else { return }

                // Build renderer off-main to keep navigation responsive during heavy loads
                let renderer = try SpineRenderer(
                    device: SpineObjects.shared.device,
                    commandQueue: SpineObjects.shared.commandQueue,
                    pixelFormat: .bgra8Unorm,
                    atlasPages: drawable.atlasPages,
                    pma: drawable.atlas.isPma
                )
                guard !Task.isCancelled else { return }

                await MainActor.run { [weak self] in
                    guard let self, self.view.window != nil, !Task.isCancelled else { return }
                    let container = self.interactionView ?? self.view
                    let sv = SpineUIView(
                        controller: controller,
                        mode: .fit,
                        alignment: .center,
                        boundsProvider: SetupPoseBounds(),
                        backgroundColor: bgColor
                    )
                    sv.attach(prebuiltRenderer: renderer, drawable: drawable)
                    sv.isHidden = true
                    sv.frame = container.bounds
                    sv.autoresizingMask = [.width, .height]
                    if !isBottom {
                        sv.layer?.isOpaque = false
                    }
                    container.addSubview(sv)
                    self.layers[index].spineView = sv
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    log("Failed to load composite layer \(basename): \(error)")
                    self?.loadedCount += 1
                    if self?.loadedCount == self?.layers.count {
                        self?.onAllLayersLoaded()
                    }
                }
            }
        }
        loadTasks.append(task)
    }

    private func onAllLayersLoaded() {
        guard view.window != nil else { return }
        reorderSubviews()

        guard let mainView = layers[mainLayerIndex].spineView else {
            showError("Main layer failed to load")
            return
        }

        modelViewer = mainView
        interactionView?.additionalViewers = layers.enumerated()
            .filter { $0.offset != mainLayerIndex }
            .compactMap { $0.element.spineView }

        setupCompositeControls()
    }

    private func reorderSubviews() {
        guard let container = interactionView ?? view as NSView? else { return }
        for layer in layers {
            if let sv = layer.spineView {
                sv.removeFromSuperview()
                container.addSubview(sv)
            }
        }
    }

    private func setupCompositeControls() {
        let mainAnims = layers[mainLayerIndex].animations
        let bar = installControlsBar()
        bar.setAnimations(mainAnims, selected: mainAnims.first)

        bar.onPlayPause = { [weak self] in
            guard let self else { return }
            guard let mainCtrl = self.layers[self.mainLayerIndex].controller else { return }
            if mainCtrl.isPlaying {
                self.forEachController { $0.pause() }
            } else {
                self.forEachController { $0.resume() }
            }
            self.controlsBar?.updatePlayState(mainCtrl.isPlaying)
        }

        bar.onSelectAnimation = { [weak self] name in
            guard let self else { return }
            for i in self.layers.indices {
                guard let ctrl = self.layers[i].controller else { continue }
                let animName: String
                if self.layers[i].animations.contains(name) {
                    animName = name
                } else {
                    animName = self.layers[i].animations.first ?? name
                }
                ctrl.animationState.setAnimationByName(
                    trackIndex: 0, animationName: animName, loop: self.isLooping)
            }
        }

        bar.onChangeSpeed = { [weak self] speed in
            self?.forEachController { $0.animationState.timeScale = speed }
        }

        bar.onToggleLoop = { [weak self] loop in
            guard let self else { return }
            self.isLooping = loop
            self.forEachController { ctrl in
                if let entry = ctrl.animationState.getCurrent(trackIndex: 0) {
                    entry.loop = loop
                }
            }
        }

        bar.onChangeBgColor = { [weak self] color in
            self?.applyBackgroundMode(.solid(color))
        }

        bar.onScrub = { [weak self] time in
            self?.forEachController { ctrl in
                if let entry = ctrl.animationState.getCurrent(trackIndex: 0) {
                    entry.trackTime = time
                }
            }
        }

        interactionView?.onPrevAnimation = { [weak self] in
            self?.controlsBar?.selectAdjacentAnimation(next: false)
        }
        interactionView?.onNextAnimation = { [weak self] in
            self?.controlsBar?.selectAdjacentAnimation(next: true)
        }

        let timer = Timer(timeInterval: 1.0/15, repeats: true) { [weak self] _ in
            guard let self,
                  let ctrl = self.layers[self.mainLayerIndex].controller,
                  let entry = ctrl.animationState.getCurrent(trackIndex: 0) else { return }
            let duration = entry.animation.duration
            let current = (entry.isComplete && !entry.loop) ? duration
                : (duration > 0 ? entry.trackTime.truncatingRemainder(dividingBy: duration) : 0)
            self.controlsBar?.updateTime(current: current, duration: duration)
        }
        RunLoop.current.add(timer, forMode: .common)
        updateTimer = timer

        loadSavedState()
        for layer in layers { layer.spineView?.isHidden = false }
        onModelReady()
    }

    // MARK: - Background

    override func applyBackgroundMode(_ mode: BackgroundMode, save: Bool = true) {
        super.applyBackgroundMode(mode, save: save)
        for (i, layer) in layers.enumerated() {
            guard let sv = layer.spineView, i != 0 else { continue }
            sv.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            sv.layer?.isOpaque = false
        }
    }

    // MARK: - Helpers

    private func forEachController(_ body: (SpineController) -> Void) {
        for layer in layers {
            if let ctrl = layer.controller { body(ctrl) }
        }
    }

    // MARK: - Snapshot

    /// Composite all layers in subview order (bottom → top) so the saved thumbnail
    /// reflects what the user actually sees, not just the main layer.
    override func saveCurrentState() {
        if let snapshot = captureCompositeSnapshot(maxSize: ModelViewerStateManager.thumbnailMaxSize) {
            ModelViewerStateManager.saveThumbnail(snapshot, for: folderURL)
        }
        ModelViewerStateManager.save(
            base: collectBaseState(), viewer: collectViewerState(), for: folderURL)
    }

    private func captureCompositeSnapshot(maxSize: CGFloat) -> CGImage? {
        let images = layers.compactMap { $0.spineView?.captureSnapshot(maxSize: maxSize) }
        guard !images.isEmpty else { return nil }
        let w = images.map { $0.width }.max() ?? 0
        let h = images.map { $0.height }.max() ?? 0
        guard w > 0, h > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        for image in images {
            ctx.draw(image, in: rect)
        }
        return ctx.makeImage()
    }

    // MARK: - Cleanup

    override func cleanup() {
        loadTasks.forEach { $0.cancel() }
        loadTasks.removeAll()
        updateTimer?.invalidate()
        updateTimer = nil
        // super.cleanup() invokes saveCurrentState before removing views, so it must
        // run while every layer's spineView is still alive — otherwise the composite
        // thumbnail would lose every non-main layer.
        super.cleanup()
        forEachController { $0.pause() }
        for i in layers.indices {
            layers[i].spineView?.removeFromSuperview()
            layers[i].spineView = nil
            layers[i].controller = nil
        }
        interactionView?.additionalViewers = []
    }
}
