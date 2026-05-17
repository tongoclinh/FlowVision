//
//  SequenceEditorView.swift
//  FlowVision
//
//  Root SwiftUI of the Sequence Editor: HSplitView between left list +
//  palette and the right authoring pane (header + canvas).
//

import SwiftUI

struct SequenceEditorView: View {
    @ObservedObject var state: SequenceEditorState

    var body: some View {
        HSplitView {
            // Column 1: sequences (rename / +/- / select)
            SequenceListView(state: state)

            // Column 2: node palette (Loop pinned top, then animations)
            PaletteView(state: state)
                .frame(minWidth: 150, idealWidth: 180, maxWidth: 220)

            // Column 3: sequence editor canvas
            VStack(spacing: 0) {
                header
                Divider()
                SequenceCanvasView(state: state)
            }
            .frame(minWidth: 360)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let entry = state.selectedEntry {
                TextField("Sequence name", text: Binding(
                    get: { entry.name },
                    set: { entry.name = $0; state.markDirty() }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            } else {
                Text("—")
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Run") { state.runSelected() }
                .disabled(state.selectedEntry == nil)

            Button("Save") { state.save() }
                .disabled(!state.isDirty)
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
