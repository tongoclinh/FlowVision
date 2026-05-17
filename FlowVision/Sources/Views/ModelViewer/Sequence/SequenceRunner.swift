//
//  SequenceRunner.swift
//  FlowVision
//
//  Engine-agnostic runtime that walks a SequenceStep tree, plays each leaf
//  through a `AnimationEngineAdapter`, and advances on completion.
//

import Foundation

/// Engine-specific glue. One implementation per animation engine (Spine, Cubism).
protocol AnimationEngineAdapter: AnyObject {
    /// Fired by the engine (on the main thread) when the current animation
    /// finishes naturally or is replaced. Set by `SequenceRunner` and invoked
    /// by the adapter; the runner ignores callbacks when not `.running`.
    var onAnimationComplete: (() -> Void)? { get set }

    /// Start playing `name`. `mixDuration` crossfades from the previous
    /// animation; pass `0` for a hard cut. Must be non-looping at the engine
    /// level — looping is handled by the runner via repeated `play` calls.
    func play(animation name: String, mixDuration: Float)

    /// Freeze the current animation in place. Resume picks up at the same
    /// time-offset. No-op if nothing is playing.
    func pause()

    /// Resume after `pause`. No-op if not paused.
    func resume()

    /// Cancel current animation; `onAnimationComplete` may still fire once
    /// for the cancelled entry and the runner is expected to ignore it.
    func stop()
}

private struct GroupFrame {
    let steps: [SequenceStep]
    let repeatCount: Int  // -1 = infinite
    var childIndex: Int = 0
    var iteration: Int = 1  // 1-based; how many times this group started

    var hasMoreIterations: Bool {
        repeatCount < 0 || iteration < repeatCount
    }
}

enum RunnerState { case idle, running, paused }

final class SequenceRunner {

    private let adapter: AnimationEngineAdapter
    private var stack: [GroupFrame] = []
    private var currentLeafRepeat: Int = 0          // 1-based; how many times current leaf played
    private var currentLeafName: String?
    private var currentLeafMaxRepeat: Int = 1       // -1 = infinite
    private var currentLeafMixDuration: Float = SequenceStep.defaultMixDuration
    private var state: RunnerState = .idle
    private var advancing = false                   // re-entry guard

    /// Notified each time a new leaf animation starts playing. Phase 7 uses
    /// this to drive the ControlsBar highlight.
    var onLeafChanged: ((String) -> Void)?

    /// Notified when the sequence finishes naturally (root group iterations
    /// exhausted). Not called after `stop()`.
    var onSequenceFinished: (() -> Void)?

    init(adapter: AnimationEngineAdapter) {
        self.adapter = adapter
        adapter.onAnimationComplete = { [weak self] in
            self?.handleAdapterComplete()
        }
    }

    var isRunning: Bool { state == .running }
    var isPaused: Bool { state == .paused }

    func start(_ sequence: AnimSequence) {
        stop()  // cancel any prior run

        // Always wrap root in a synthetic frame so the cursor logic is uniform.
        let rootFrame: GroupFrame
        switch sequence.root {
        case let .group(steps, repeatCount):
            rootFrame = GroupFrame(steps: steps, repeatCount: repeatCount)
        case .animation:
            rootFrame = GroupFrame(steps: [sequence.root], repeatCount: 1)
        }
        stack = [rootFrame]
        state = .running
        advance()
    }

    func stop() {
        let wasRunning = state != .idle
        state = .idle
        stack.removeAll()
        currentLeafName = nil
        currentLeafRepeat = 0
        if wasRunning {
            adapter.stop()
        }
    }

    func pause() {
        guard state == .running else { return }
        adapter.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        adapter.resume()
        state = .running
    }

    // MARK: - Internal

    private func handleAdapterComplete() {
        // Ignore late callbacks from a cancelled or paused run.
        guard state == .running, !advancing else { return }
        advance()
    }

    private func advance() {
        guard state == .running else { return }
        advancing = true
        defer { advancing = false }

        // If a leaf is currently playing, decide whether to repeat or move on.
        if let name = currentLeafName {
            if currentLeafMaxRepeat < 0 || currentLeafRepeat < currentLeafMaxRepeat {
                currentLeafRepeat += 1
                onLeafChanged?(name)
                adapter.play(animation: name, mixDuration: currentLeafMixDuration)
                return
            }
            currentLeafName = nil  // leaf done; fall through to find the next one
        }

        // Walk forward through the stack until we find a leaf or empty out.
        var safety = 0
        while !stack.isEmpty {
            safety += 1
            if safety > 1024 {
                // No leaves found in a deep tree — bail rather than spin forever.
                NSLog("SequenceRunner: aborting — exceeded 1024 group traversals without a leaf")
                stop()
                return
            }

            // Peek top frame, look at its next step.
            var frame = stack.removeLast()
            if frame.childIndex >= frame.steps.count {
                // Frame is past its last child; consider another iteration.
                if frame.repeatCount < 0 || frame.iteration < frame.repeatCount {
                    frame.iteration += 1
                    frame.childIndex = 0
                    stack.append(frame)
                    continue
                }
                // Group done — drop the frame and keep walking the parent.
                continue
            }

            let step = frame.steps[frame.childIndex]
            frame.childIndex += 1
            stack.append(frame)

            switch step {
            case let .animation(name, repeatCount, mixDuration):
                currentLeafName = name
                currentLeafRepeat = 1
                currentLeafMaxRepeat = repeatCount
                currentLeafMixDuration = mixDuration
                onLeafChanged?(name)
                adapter.play(animation: name, mixDuration: mixDuration)
                return
            case let .group(steps, repeatCount):
                stack.append(GroupFrame(steps: steps, repeatCount: repeatCount))
                // Loop continues to descend into the new frame.
            }
        }

        // Stack exhausted — sequence done.
        state = .idle
        onSequenceFinished?()
    }
}
