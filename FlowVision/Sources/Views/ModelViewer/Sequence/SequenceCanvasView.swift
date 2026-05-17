//
//  SequenceCanvasView.swift
//  FlowVision
//
//  New block-stack canvas replacing the tree-based SequenceTreeView.
//  Phase 1: renders the existing StepNode tree as a vertical stack of
//  BlockCardView / LoopCardView with tap-to-select. Phase 2 will
//  interleave drop strips between cards. Phase 3 wires inline edit
//  on the selected card.
//

import SwiftUI
import AppKit

struct SequenceCanvasView: View {
    @ObservedObject var state: SequenceEditorState

    var body: some View {
        if state.selectedEntry == nil {
            placeholder("Select or create a sequence")
        } else if let entry = state.selectedEntry, entry.rootNode.children.isEmpty {
            emptySequenceHint
        } else if let entry = state.selectedEntry {
            cardStack(entry: entry)
        }
    }

    private func cardStack(entry: SequenceEditorEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(entry.rootNode.children.enumerated()), id: \.element.id) { idx, child in
                    InsertionDropStrip(state: state, parent: entry.rootNode, index: idx)
                    childView(for: child)
                }
                InsertionDropStrip(
                    state: state,
                    parent: entry.rootNode,
                    index: entry.rootNode.children.count
                )
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func childView(for child: StepNode) -> some View {
        switch child.kind {
        case .animation:
            BlockCardView(state: state, node: child)
        case .group:
            LoopCardView(state: state, node: child)
        }
    }

    private var emptySequenceHint: some View {
        // Accept drops onto the empty canvas so the user can start a sequence
        // by dragging from the palette directly onto this area.
        EmptySequenceDropView(state: state)
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundColor(.secondary)
                .italic()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptySequenceDropView: View {
    @ObservedObject var state: SequenceEditorState
    @State private var hovered: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.left.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.secondary)
            Text("Drag a block from the palette to start")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(hovered
                    ? SwiftUI.Color(NSColor.controlAccentColor).opacity(0.08)
                    : SwiftUI.Color.clear)
        .contentShape(Rectangle())
        .onDrop(of: [BlockDragPayload.pasteboardType],
                isTargeted: $hovered) { providers in
            guard let root = state.selectedEntry?.rootNode else { return false }
            BlockDragPayload.decode(from: providers) { payload in
                guard let payload = payload else { return }
                state.handleDrop(payload, into: root, at: 0)
            }
            return true
        }
    }
}
