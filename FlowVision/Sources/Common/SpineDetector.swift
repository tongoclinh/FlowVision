//
//  SpineDetector.swift
//  FlowVision
//

import Foundation

struct SpineModelFiles {
    let skeleton: URL
    let atlas: URL
}

struct SpineDetector: ModelDetector {
    static func isModelFolder(at url: URL) -> Bool {
        isSpineFolder(url)
    }

    static func isSpineFolder(_ url: URL) -> Bool {
        guard url.hasDirectoryPath else { return false }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return false }
        let hasSkel = contents.contains { $0.pathExtension.lowercased() == "skel" }
        let hasAtlas = contents.contains { $0.pathExtension.lowercased() == "atlas" }
        guard hasAtlas else { return false }
        if hasSkel { return true }
        let atlasBaseNames = Set(
            contents.filter { $0.pathExtension.lowercased() == "atlas" }
                .map { $0.deletingPathExtension().lastPathComponent }
        )
        return contents.contains {
            $0.pathExtension.lowercased() == "json"
                && atlasBaseNames.contains($0.deletingPathExtension().lastPathComponent)
        }
    }

    static func findSpineFiles(in url: URL) -> [SpineModelFiles] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return [] }

        let atlasByBase = Dictionary(
            contents.filter { $0.pathExtension.lowercased() == "atlas" }
                .map { ($0.deletingPathExtension().lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var results = [SpineModelFiles]()

        // .skel files matched to same-name .atlas
        for file in contents where file.pathExtension.lowercased() == "skel" {
            let base = file.deletingPathExtension().lastPathComponent
            if let atlas = atlasByBase[base] {
                results.append(SpineModelFiles(skeleton: file, atlas: atlas))
            }
        }

        // .json files matched to same-name .atlas (only if no .skel with that name)
        if results.isEmpty {
            for file in contents where file.pathExtension.lowercased() == "json" {
                let base = file.deletingPathExtension().lastPathComponent
                if let atlas = atlasByBase[base] {
                    results.append(SpineModelFiles(skeleton: file, atlas: atlas))
                }
            }
        }

        // Fallback: single skel + single atlas (unmatched names)
        if results.isEmpty {
            let skels = contents.filter { $0.pathExtension.lowercased() == "skel" }
            let atlases = contents.filter { $0.pathExtension.lowercased() == "atlas" }
            if skels.count == 1, atlases.count == 1 {
                results.append(SpineModelFiles(skeleton: skels[0], atlas: atlases[0]))
            }
        }

        return results
    }
}
