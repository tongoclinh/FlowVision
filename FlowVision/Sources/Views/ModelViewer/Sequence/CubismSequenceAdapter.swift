//
//  CubismSequenceAdapter.swift
//  FlowVision
//
//  Drives a CubismUIView via SequenceRunner. Uses the bridge's
//  startMotionInGroup:...:fadeInSeconds:completion: variant added in Phase 1
//  so mixDuration crossfades match Spine's parity.
//

import Foundation

final class CubismSequenceAdapter: AnimationEngineAdapter {

    private weak var view: CubismUIView?

    var onAnimationComplete: (() -> Void)?

    init(view: CubismUIView) {
        self.view = view
    }

    func play(animation name: String, mixDuration: Float) {
        guard let v = view, let info = v.motionInfo(forName: name) else {
            // Missing target — fire completion async so the runner doesn't
            // stall (mirrors the bridge's motion-rejected fallback path).
            DispatchQueue.main.async { [weak self] in self?.onAnimationComplete?() }
            return
        }
        v.modelHandle.startMotion(
            inGroup: info.group,
            at: info.index,
            priority: 3,
            fadeInSeconds: mixDuration,
            completion: { [weak self] in
                self?.onAnimationComplete?()
            })
    }

    func pause() {
        view?.animationPaused = true
    }

    func resume() {
        view?.animationPaused = false
    }

    func stop() {
        view?.modelHandle.stopAllMotions()
    }
}
