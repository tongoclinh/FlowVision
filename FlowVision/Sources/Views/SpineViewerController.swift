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
    }

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
                    let sv = SpineUIView(
                        from: .drawable(drawable),
                        controller: controller,
                        mode: .fit,
                        alignment: .center,
                        boundsProvider: SetupPoseBounds(),
                        backgroundColor: .black
                    )
                    sv.frame = self.view.bounds
                    sv.autoresizingMask = [.width, .height]
                    self.view.addSubview(sv)
                    self.spineView = sv
                }
            } catch {
                await MainActor.run {
                    self.showError("Failed to load Spine model:\n\(error)\n\nFile: \(skelURL.lastPathComponent)\nAtlas: \(atlasURL.lastPathComponent)")
                }
            }
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
        spineView?.isPaused = true
        spineView?.removeFromSuperview()
        spineView = nil
        spineController = nil
    }

    deinit {
        cleanup()
    }
}
