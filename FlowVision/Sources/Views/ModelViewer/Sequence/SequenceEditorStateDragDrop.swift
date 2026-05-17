//
//  SequenceEditorStateDragDrop.swift
//  FlowVision
//
//  Drag-drop mutation helpers on SequenceEditorState. Split out of the
//  main file to keep both files under the 200-LoC soft cap.
//

import Foundation

extension SequenceEditorState {

    /// Insert a fresh animation node carrying the given name at `(parent, index)`.
    func insertAnimation(named name: String, into parent: StepNode, at index: Int) {
        let resolved = name.isEmpty ? (availableAnimations.first ?? "") : name
        let node = StepNode(
            kind: .animation,
            name: resolved,
            repeatCount: 1
        )
        node.parent = parent
        let safeIdx = max(0, min(index, parent.children.count))
        parent.children.insert(node, at: safeIdx)
        selectedNodeId = node.id
        markDirty()
    }

    /// Insert a fresh empty loop container at `(parent, index)`.
    func insertLoop(into parent: StepNode, at index: Int) {
        let node = StepNode(kind: .group, repeatCount: 1)
        node.parent = parent
        let safeIdx = max(0, min(index, parent.children.count))
        parent.children.insert(node, at: safeIdx)
        selectedNodeId = node.id
        markDirty()
    }

    /// Move an existing node to a new `(parent, index)`. Refuses moves that
    /// would put a node inside one of its own descendants (cycle guard).
    /// Selection follows the moved node.
    func moveNode(id nodeId: UUID, to parent: StepNode, atIndex index: Int) {
        guard let entry = selectedEntry,
              let node = findNode(id: nodeId, in: entry.rootNode) else { return }
        if node === parent { return }
        if isAncestor(node, of: parent) { return }

        // When moving within the same parent FROM an earlier slot, the
        // upcoming `remove()` shifts every later sibling left by one — so
        // the target index needs to compensate or we land one slot too far
        // right. (Visual "no-op" drops would otherwise reorder unexpectedly.)
        var targetIdx = index
        if node.parent === parent,
           let curIdx = parent.children.firstIndex(where: { $0 === node }),
           curIdx < index {
            targetIdx -= 1
        }

        node.remove()
        node.parent = parent
        let safeIdx = max(0, min(targetIdx, parent.children.count))
        parent.children.insert(node, at: safeIdx)
        selectedNodeId = node.id
        markDirty()
    }

    /// Single entry point for all drop kinds. Container drop zones and
    /// `InsertionDropStrip` route through this so the call site stays one
    /// line.
    func handleDrop(_ payload: BlockDragPayload, into parent: StepNode, at index: Int) {
        switch payload {
        case .paletteAnimation(let name):
            insertAnimation(named: name, into: parent, at: index)
        case .paletteLoop:
            insertLoop(into: parent, at: index)
        case .existing(let id):
            moveNode(id: id, to: parent, atIndex: index)
        }
    }

    /// Walks the parent chain to detect cycles. `candidate` is the node we
    /// are about to move; `target` is the proposed new parent. Returns true
    /// if `target` is `candidate` itself or one of its descendants.
    func isAncestor(_ candidate: StepNode, of target: StepNode) -> Bool {
        var p: StepNode? = target
        while let cur = p {
            if cur === candidate { return true }
            p = cur.parent
        }
        return false
    }
}
