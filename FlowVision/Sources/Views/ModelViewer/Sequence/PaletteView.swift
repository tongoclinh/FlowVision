//
//  PaletteView.swift
//  FlowVision
//
//  Scrollable palette of draggable blocks: one chip per available
//  animation (drag onto canvas to insert with that name pre-filled), plus
//  a separate Loop chip for empty containers.
//

import SwiftUI
import AppKit

struct PaletteView: View {
    @ObservedObject var state: SequenceEditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PALETTE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    loopChip
                    if !state.availableAnimations.isEmpty {
                        Divider().padding(.vertical, 2)
                        ForEach(state.availableAnimations, id: \.self) { name in
                            animationChip(name: name)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    private var loopChip: some View {
        chip(icon: "arrow.triangle.2.circlepath",
             tint: .orange,
             label: "Loop")
            .onDrag {
                BlockDragPayload.paletteLoop.itemProvider()
            }
            .help("Drag onto canvas to add an empty loop container")
    }

    private func animationChip(name: String) -> some View {
        chip(icon: "play.fill",
             tint: .blue,
             label: name)
            .onDrag {
                BlockDragPayload.paletteAnimation(name: name).itemProvider()
            }
            .help("Drag onto canvas to add this animation as a step")
    }

    private func chip(icon: String, tint: SwiftUI.Color, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(SwiftUI.Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(SwiftUI.Color(NSColor.separatorColor), lineWidth: 1)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
}
