//
//  LoopCardView.swift
//  FlowVision
//
//  Loop container card. One-row header (same shape as BlockCardView) +
//  nested children column. Children area accepts drops to reparent.
//

import SwiftUI
import AppKit

struct LoopCardView: View {
    @ObservedObject var state: SequenceEditorState
    @ObservedObject var node: StepNode
    @State private var containerHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            childrenColumn
        }
        .padding(8)
        .background(loopBackground)
        .overlay(loopBorder)
        .overlay(containerDropHighlight)
        .cornerRadius(8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.orange)
                .font(.system(size: 14, weight: .semibold))

            Text("Loop")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            if isInfiniteWithSiblingsAfter {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .help("Successors will never play — this loop is infinite")
            }

            Spacer(minLength: 4)

            RepeatPill(node: node, state: state)
            ungroupMenu
            DeleteButton { state.deleteSelected(node: node) }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture { state.selectedNodeId = node.id }
        .onDrag {
            BlockDragPayload.existing(nodeId: node.id).itemProvider()
        }
    }

    private var ungroupMenu: some View {
        Menu {
            Button("Ungroup") { state.ungroup(node: node) }
                .disabled(node.parent == nil)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More actions")
    }

    private var childrenColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            if node.children.isEmpty {
                Text("Empty loop — drag a block here")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 4)
                    .padding(.leading, 8)
            } else {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { idx, child in
                    InsertionDropStrip(state: state, parent: node, index: idx)
                    childView(for: child)
                }
                InsertionDropStrip(state: state, parent: node, index: node.children.count)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDrop(of: [BlockDragPayload.pasteboardType],
                isTargeted: $containerHovered) { providers in
            BlockDragPayload.decode(from: providers) { payload in
                guard let payload = payload else { return }
                state.handleDrop(payload, into: node, at: node.children.count)
            }
            return true
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

    @ViewBuilder private var containerDropHighlight: some View {
        if containerHovered {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    SwiftUI.Color(NSColor.controlAccentColor),
                    lineWidth: 2.5
                )
        }
    }

    private var isInfiniteWithSiblingsAfter: Bool {
        guard node.repeatCount < 0,
              let parent = node.parent,
              let idx = parent.children.firstIndex(where: { $0 === node })
        else { return false }
        return idx < parent.children.count - 1
    }

    private var loopBackground: SwiftUI.Color {
        state.selectedNodeId == node.id
            ? SwiftUI.Color(NSColor.controlAccentColor).opacity(0.10)
            : SwiftUI.Color(NSColor.windowBackgroundColor).opacity(0.6)
    }

    private var loopBorder: some View {
        let selected = state.selectedNodeId == node.id
        return RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                selected
                    ? SwiftUI.Color(NSColor.controlAccentColor)
                    : SwiftUI.Color.orange.opacity(0.55),
                lineWidth: selected ? 2 : 1.5
            )
    }
}
