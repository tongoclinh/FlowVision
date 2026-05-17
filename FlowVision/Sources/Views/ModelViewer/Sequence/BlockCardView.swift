//
//  BlockCardView.swift
//  FlowVision
//
//  Compact one-row card for an animation step. Animation name is locked
//  once the chip is dragged from the palette — no inline picker. The row
//  is always shown the same way; selection only changes the border tint.
//

import SwiftUI
import AppKit

struct BlockCardView: View {
    @ObservedObject var state: SequenceEditorState
    @ObservedObject var node: StepNode

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .foregroundColor(.blue)
                .font(.system(size: 14, weight: .semibold))

            Text(displayName)
                .font(.system(size: 13))
                .foregroundColor(state.availableAnimations.contains(node.name) ? .primary : .red)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            RepeatPill(node: node, state: state)
            DeleteButton { state.deleteSelected(node: node) }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(cardBackground)
        .overlay(cardBorder)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { state.selectedNodeId = node.id }
        .onDrag {
            BlockDragPayload.existing(nodeId: node.id).itemProvider()
        }
    }

    private var displayName: String {
        state.availableAnimations.contains(node.name)
            ? node.name
            : "\(node.name) (missing)"
    }

    private var cardBackground: SwiftUI.Color {
        state.selectedNodeId == node.id
            ? SwiftUI.Color(NSColor.controlAccentColor).opacity(0.22)
            : SwiftUI.Color(NSColor.controlBackgroundColor)
    }

    private var cardBorder: some View {
        let selected = state.selectedNodeId == node.id
        return RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                selected
                    ? SwiftUI.Color(NSColor.controlAccentColor)
                    : SwiftUI.Color(NSColor.separatorColor),
                lineWidth: selected ? 1.5 : 1
            )
    }
}
