//
//  SequenceEditorState.swift
//  FlowVision
//
//  ObservableObject backing the Sequence Editor window. All mutations route
//  through this object so the dirty flag stays consistent and SwiftUI's
//  top-level objectWillChange fires when nested StepNode children change.
//

import Foundation
import Combine

final class SequenceEditorEntry: Identifiable, ObservableObject {
    let id = UUID()
    @Published var name: String
    @Published var rootNode: StepNode

    init(name: String, rootNode: StepNode) {
        self.name = name
        self.rootNode = rootNode
    }

    func toAnimSequence() -> AnimSequence {
        AnimSequence(name: name, root: rootNode.toStep())
    }
}

final class SequenceEditorState: ObservableObject {

    @Published var entries: [SequenceEditorEntry]
    @Published var selectedEntryId: UUID?
    @Published var selectedNodeId: UUID?
    @Published private(set) var isDirty: Bool = false

    let availableAnimations: [String]
    let onSave: ([AnimSequence]) -> Void
    let onRun: (AnimSequence) -> Void

    /// Persisted-state snapshot used to roll back via Discard.
    private var savedSnapshot: [AnimSequence]

    init(initial: [AnimSequence],
         availableAnimations: [String],
         onSave: @escaping ([AnimSequence]) -> Void,
         onRun: @escaping (AnimSequence) -> Void) {
        self.availableAnimations = availableAnimations
        self.onSave = onSave
        self.onRun = onRun
        self.savedSnapshot = initial
        self.entries = initial.map {
            SequenceEditorEntry(name: $0.name, rootNode: StepNode(from: $0.root))
        }
        self.selectedEntryId = self.entries.first?.id
    }

    var selectedEntry: SequenceEditorEntry? {
        guard let id = selectedEntryId else { return nil }
        return entries.first(where: { $0.id == id })
    }

    var selectedNode: StepNode? {
        guard let id = selectedNodeId, let entry = selectedEntry else { return nil }
        return findNode(id: id, in: entry.rootNode)
    }

    func findNode(id: UUID, in node: StepNode) -> StepNode? {
        if node.id == id { return node }
        for child in node.children {
            if let found = findNode(id: id, in: child) { return found }
        }
        return nil
    }

    // MARK: - Sequence-level operations

    func addSequence() {
        let root = StepNode(kind: .group, repeatCount: 1)
        let entry = SequenceEditorEntry(name: defaultSequenceName(), rootNode: root)
        entries.append(entry)
        selectedEntryId = entry.id
        selectedNodeId = nil
        markDirty()
    }

    func removeSelectedSequence() {
        guard let id = selectedEntryId,
              let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: idx)
        selectedEntryId = entries.first?.id
        selectedNodeId = nil
        markDirty()
    }

    func renameSelectedSequence(to newName: String) {
        guard let entry = selectedEntry, entry.name != newName else { return }
        entry.name = newName
        markDirty()
    }

    private func defaultSequenceName() -> String {
        var n = 1
        while entries.contains(where: { $0.name == "Sequence \(n)" }) { n += 1 }
        return "Sequence \(n)"
    }

    // MARK: - Node-level operations

    /// Insert a new animation leaf next to the selected node (or as last child
    /// of the selected group / root if no node is selected).
    func addAnimation() {
        let firstAnim = availableAnimations.first ?? ""
        let newNode = StepNode(kind: .animation, name: firstAnim, repeatCount: 1)
        insertNextToSelection(newNode)
    }

    func addGroup() {
        let newNode = StepNode(kind: .group, repeatCount: 1)
        insertNextToSelection(newNode)
    }

    private func insertNextToSelection(_ node: StepNode) {
        guard let entry = selectedEntry else { return }
        if let sel = selectedNode {
            if sel.kind == .group {
                sel.addChild(node)
            } else if let parent = sel.parent,
                      let idx = parent.children.firstIndex(where: { $0 === sel }) {
                node.parent = parent
                parent.children.insert(node, at: idx + 1)
            } else {
                entry.rootNode.addChild(node)
            }
        } else {
            entry.rootNode.addChild(node)
        }
        selectedNodeId = node.id
        markDirty()
    }

    func groupSelected() {
        guard let sel = selectedNode, sel !== selectedEntry?.rootNode else { return }
        if let wrapped = sel.wrapInGroup() {
            selectedNodeId = wrapped.id
            markDirty()
        }
    }

    func ungroupSelected() {
        guard let sel = selectedNode else { return }
        ungroup(node: sel)
    }

    /// Ungroup any loop node (not just the selected one). Splices its
    /// children into its parent and removes the loop. No-op for animation
    /// nodes or the root.
    func ungroup(node: StepNode) {
        guard node.kind == .group, node !== selectedEntry?.rootNode else { return }
        if selectedNodeId == node.id { selectedNodeId = nil }
        node.ungroup()
        markDirty()
    }

    func moveSelectionUp() {
        guard let sel = selectedNode else { return }
        sel.moveUp()
        markDirty()
    }

    func moveSelectionDown() {
        guard let sel = selectedNode else { return }
        sel.moveDown()
        markDirty()
    }

    func deleteSelected() {
        guard let sel = selectedNode else { return }
        deleteSelected(node: sel)
    }

    /// Delete a specific node (used by the inline trash button on each
    /// card; not restricted to the currently-selected node).
    func deleteSelected(node: StepNode) {
        guard node !== selectedEntry?.rootNode else { return }
        if selectedNodeId == node.id { selectedNodeId = nil }
        node.remove()
        markDirty()
    }

    // MARK: - Persistence

    func save() {
        let sequences = entries.map { $0.toAnimSequence() }
        onSave(sequences)
        savedSnapshot = sequences
        isDirty = false
    }

    func discard() {
        entries = savedSnapshot.map {
            SequenceEditorEntry(name: $0.name, rootNode: StepNode(from: $0.root))
        }
        selectedEntryId = entries.first?.id
        selectedNodeId = nil
        isDirty = false
    }

    /// Marks the editor dirty AND nudges SwiftUI: nested StepNode @Published
    /// changes don't always propagate to the top-level state, so we publish
    /// the state itself to force a re-render of dependent views.
    func markDirty() {
        isDirty = true
        objectWillChange.send()
    }

    func runSelected() {
        guard let entry = selectedEntry else { return }
        onRun(entry.toAnimSequence())
    }
}
