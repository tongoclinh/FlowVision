//
//  InsertionDropStrip.swift
//  FlowVision
//
//  Thin transparent strip between sibling cards. Shows a 3 pt accent line
//  when a drag is hovering over it; accepts BlockDragPayload drops at the
//  given (parent, index) position.
//

import SwiftUI
import AppKit

struct InsertionDropStrip: View {
    @ObservedObject var state: SequenceEditorState
    let parent: StepNode
    let index: Int
    @State private var hovered: Bool = false

    var body: some View {
        ZStack {
            // Invisible-but-tappable backing so the drop area is wider than
            // the visible line. 8 pt vertical reach feels good in testing.
            SwiftUI.Color.clear
                .frame(height: 8)

            if hovered {
                Capsule()
                    .fill(SwiftUI.Color(NSColor.controlAccentColor))
                    .frame(height: 3)
                    .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [BlockDragPayload.pasteboardType],
                isTargeted: $hovered) { providers in
            BlockDragPayload.decode(from: providers) { payload in
                guard let payload = payload else { return }
                state.handleDrop(payload, into: parent, at: index)
            }
            return true
        }
    }
}
