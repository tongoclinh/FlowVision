//
//  ModelViewerState.swift
//  FlowVision
//

import AppKit

struct CodablePoint: Codable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct ModelViewerState: Codable {
    var version: Int = 1

    var zoomScale: Double?
    var panCenter: CodablePoint?
    var selectedAnimation: String?
    var playbackSpeed: Float?
    var isLooping: Bool?
}

enum ModelViewerStateManager {

    static let fileName = ".flowvision.json"

    static func loadData(for folderURL: URL) -> Data? {
        let url = folderURL.appendingPathComponent(fileName)
        return try? Data(contentsOf: url)
    }

    static func decodeBase(from data: Data) -> ModelViewerState? {
        try? JSONDecoder().decode(ModelViewerState.self, from: data)
    }

    // Keys are flat-merged: viewer keys must not collide with base keys.
    static func save(base: ModelViewerState, viewer: Encodable?, for folderURL: URL) {
        let url = folderURL.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            var dict = try encodeToDictionary(base, encoder: encoder)
            if let viewer {
                if let viewerDict = try? encodeToDictionary(viewer, encoder: encoder) {
                    dict.merge(viewerDict) { _, new in new }
                }
            }
            let data = try JSONSerialization.data(
                withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            log("Failed to save sidecar at \(url.path): \(error)")
        }
    }

    private static func encodeToDictionary(
        _ value: Encodable, encoder: JSONEncoder
    ) throws -> [String: Any] {
        let data = try encoder.encode(value)
        let obj = try JSONSerialization.jsonObject(with: data)
        return obj as? [String: Any] ?? [:]
    }
}
