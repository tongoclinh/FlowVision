//
//  SequenceNode.swift
//  FlowVision
//
//  Mutable class mirror of SequenceStep for the SwiftUI sequence editor.
//  Identity (`id`) is stable within an editor session and not persisted —
//  selection / expansion state is regenerated on reload.
//

import Foundation
import Combine

final class StepNode: Identifiable, ObservableObject {
    enum Kind { case animation, group }

    let id = UUID()
    @Published var kind: Kind
    @Published var name: String
    @Published var repeatCount: Int
    @Published var mixDuration: Float
    @Published var children: [StepNode]
    weak var parent: StepNode?

    init(kind: Kind,
         name: String = "",
         repeatCount: Int = 1,
         mixDuration: Float = SequenceStep.defaultMixDuration,
         children: [StepNode] = [],
         parent: StepNode? = nil) {
        self.kind = kind
        self.name = name
        self.repeatCount = repeatCount
        self.mixDuration = mixDuration
        self.children = children
        self.parent = parent
        for child in children { child.parent = self }
    }

    convenience init(from step: SequenceStep, parent: StepNode? = nil) {
        switch step {
        case let .animation(name, repeatCount, mixDuration):
            self.init(kind: .animation,
                      name: name,
                      repeatCount: repeatCount,
                      mixDuration: mixDuration,
                      parent: parent)
        case let .group(steps, repeatCount):
            // Build kids with nil parent first; designated init's children loop
            // rewires their parent pointer to `self` once it exists.
            let kids = steps.map { StepNode(from: $0, parent: nil) }
            self.init(kind: .group,
                      repeatCount: repeatCount,
                      children: kids,
                      parent: parent)
        }
    }

    func toStep() -> SequenceStep {
        switch kind {
        case .animation:
            return .animation(name: name,
                              repeatCount: repeatCount,
                              mixDuration: mixDuration)
        case .group:
            return .group(steps: children.map { $0.toStep() },
                          repeatCount: repeatCount)
        }
    }

    // MARK: - Editor operations

    func addChild(_ node: StepNode) {
        guard kind == .group else { return }
        node.parent = self
        children.append(node)
    }

    func remove() {
        guard let p = parent, let idx = p.children.firstIndex(where: { $0 === self }) else { return }
        p.children.remove(at: idx)
        parent = nil
    }

    /// Move this node one slot earlier within its parent's children. No-op if
    /// already first or if the node is detached.
    func moveUp() {
        guard let p = parent, let idx = p.children.firstIndex(where: { $0 === self }), idx > 0 else { return }
        p.children.swapAt(idx, idx - 1)
    }

    func moveDown() {
        guard let p = parent, let idx = p.children.firstIndex(where: { $0 === self }),
              idx < p.children.count - 1 else { return }
        p.children.swapAt(idx, idx + 1)
    }

    /// Replace this node in its parent with a new `.group` node that contains
    /// this node as its sole child. Useful for "wrap selection in loop".
    @discardableResult
    func wrapInGroup() -> StepNode? {
        guard let p = parent, let idx = p.children.firstIndex(where: { $0 === self }) else { return nil }
        let group = StepNode(kind: .group, repeatCount: 1, parent: p)
        self.parent = group
        group.children = [self]
        p.children[idx] = group
        return group
    }

    /// Inverse of `wrapInGroup`. Splice this group's children into the parent
    /// and remove this group. No-op for animation nodes or the root.
    func ungroup() {
        guard kind == .group,
              let p = parent,
              let idx = p.children.firstIndex(where: { $0 === self }) else { return }
        for child in children { child.parent = p }
        p.children.replaceSubrange(idx...idx, with: children)
        self.parent = nil
        self.children = []
    }
}
