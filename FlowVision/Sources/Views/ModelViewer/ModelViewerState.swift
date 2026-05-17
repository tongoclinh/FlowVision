//
//  ModelViewerState.swift
//  FlowVision
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

struct CodablePoint: Codable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct CompositeConfig: Codable {
    var layers: [String]
    var mainLayer: String?
}

struct ModelViewerState: Codable {
    var version: Int = 1

    var zoomScale: Double?
    var panCenter: CodablePoint?
    var selectedAnimation: String?
    var playbackSpeed: Float?
    var isLooping: Bool?
    var sequences: [AnimSequence]?
}

extension Notification.Name {
    /// Posted on main thread after a model folder's thumbnail PNG is written.
    /// userInfo["folderURL"] = URL of the model folder (not the thumbnail itself).
    static let modelThumbnailDidUpdate = Notification.Name("FlowVision.modelThumbnailDidUpdate")
}

enum ModelViewerStateManager {

    static let fileName = ".flowvision.json"
    static let thumbnailFileName = ".flowvision-thumb.png"
    /// Sized for 2× retina grid display; ModelSnapshot.resize only scales down,
    /// so this acts as a cap rather than an upscale.
    static let thumbnailMaxSize: CGFloat = 1024

    static func thumbnailURL(for folderURL: URL) -> URL {
        folderURL.appendingPathComponent(thumbnailFileName)
    }

    /// Write CGImage to `.flowvision-thumb.png` in the model folder.
    /// Silently no-ops on failure (read-only volumes, permission errors).
    /// Posts `.modelThumbnailDidUpdate` on success so grid listeners can invalidate caches.
    static func saveThumbnail(_ image: CGImage, for folderURL: URL) {
        let url = thumbnailURL(for: folderURL)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .modelThumbnailDidUpdate,
                object: nil,
                userInfo: ["folderURL": folderURL]
            )
        }
    }

    static func loadData(for folderURL: URL) -> Data? {
        let url = folderURL.appendingPathComponent(fileName)
        return try? Data(contentsOf: url)
    }

    static func decodeBase(from data: Data) -> ModelViewerState? {
        try? JSONDecoder().decode(ModelViewerState.self, from: data)
    }

    static func loadCompositeConfig(for folderURL: URL) -> CompositeConfig? {
        guard let data = loadData(for: folderURL),
              let config = try? JSONDecoder().decode(CompositeConfig.self, from: data),
              !config.layers.isEmpty else { return nil }
        return config
    }

    // Keys are flat-merged: viewer keys must not collide with base keys.
    // Preserves unknown keys (e.g. layers, mainLayer) from existing sidecar.
    static func save(base: ModelViewerState, viewer: Encodable?, for folderURL: URL) {
        let url = folderURL.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            var dict = [String: Any]()
            if let existing = try? Data(contentsOf: url),
               let existingDict = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
                dict = existingDict
            }
            dict.merge(try encodeToDictionary(base, encoder: encoder)) { _, new in new }
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
