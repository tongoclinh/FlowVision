//
//  SpineSequenceAdapter.swift
//  FlowVision
//
//  Drives one or more SpineControllers via SequenceRunner. The first
//  controller is the "main" layer — its track is observed for the per-leaf
//  `complete` event. Secondary layers play in sync without listeners. When a
//  secondary layer lacks a named animation, it falls back to its first
//  animation (mirroring SpineCompositeController's existing behavior).
//

import Foundation
import SpineCppLite

final class SpineSequenceAdapter: AnimationEngineAdapter {

    private struct Layer {
        weak var controller: SpineController?
        /// Animation names this layer supports. `nil` disables fallback —
        /// the leaf name is forwarded as-is (single-anim path).
        let animations: [String]?
    }

    private let layers: [Layer]
    private let trackIndex: Int32 = 0

    var onAnimationComplete: (() -> Void)?

    /// Single-layer (non-composite) playback. Used by SpineViewerController.
    convenience init(controller: SpineController) {
        self.init(layers: [Layer(controller: controller, animations: nil)])
    }

    /// Composite playback. `main` receives the `complete` listener; each
    /// secondary plays the same leaf with per-layer fallback when missing.
    convenience init(main: SpineController,
                     mainAnimations: [String],
                     secondaries: [(SpineController, [String])]) {
        var arr: [Layer] = [Layer(controller: main, animations: mainAnimations)]
        for (ctrl, anims) in secondaries {
            arr.append(Layer(controller: ctrl, animations: anims))
        }
        self.init(layers: arr)
    }

    private init(layers: [Layer]) {
        self.layers = layers
    }

    func play(animation name: String, mixDuration: Float) {
        // If the main layer's controller has gone away (e.g. composite parent
        // disposed mid-sequence), fire completion async so the runner doesn't
        // stall waiting for an event that will never come.
        if let firstLayer = layers.first, firstLayer.controller == nil {
            DispatchQueue.main.async { [weak self] in self?.onAnimationComplete?() }
            return
        }
        for (i, layer) in layers.enumerated() {
            guard let ctrl = layer.controller else { continue }
            let resolvedName: String
            if let anims = layer.animations, !anims.contains(name) {
                // Layer doesn't have this leaf — fall back to its first animation,
                // matching SpineCompositeController.onSelectAnimation behavior.
                resolvedName = anims.first ?? name
            } else {
                resolvedName = name
            }
            if let prev = ctrl.animationState.getCurrent(trackIndex: trackIndex)?.animation.name {
                ctrl.animationStateData.setMixByName(
                    fromName: prev, toName: resolvedName, duration: mixDuration)
            }
            let entry = ctrl.animationState.setAnimationByName(
                trackIndex: trackIndex, animationName: resolvedName, loop: false)
            if i == 0 {
                // Only the main layer drives runner advancement. Secondary
                // completions are ignored to avoid double-fire.
                ctrl.animationStateWrapper.setTrackEntryListener(entry: entry) { [weak self] type, _, _ in
                    if type == SPINE_EVENT_TYPE_COMPLETE {
                        self?.onAnimationComplete?()
                    }
                }
            }
        }
    }

    func pause() {
        for layer in layers {
            layer.controller?.animationState.getCurrent(trackIndex: trackIndex)?.timeScale = 0
        }
    }

    func resume() {
        for layer in layers {
            layer.controller?.animationState.getCurrent(trackIndex: trackIndex)?.timeScale = 1
        }
    }

    func stop() {
        for layer in layers {
            layer.controller?.animationState.clearTrack(trackIndex: trackIndex)
        }
    }
}
