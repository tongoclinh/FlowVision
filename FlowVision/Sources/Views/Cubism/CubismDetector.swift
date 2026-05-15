//
//  CubismDetector.swift
//  FlowVision
//

import Foundation

struct CubismModelFiles {
    let modelJson: URL
    let moc3: URL
}

struct CubismDetector: ModelDetector {
    static func isModelFolder(at url: URL) -> Bool {
        isCubismFolder(url)
    }

    static func isCubismFolder(_ url: URL) -> Bool {
        guard url.hasDirectoryPath else { return false }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return false }
        let hasModel3 = contents.contains { $0.lastPathComponent.hasSuffix(".model3.json") }
        let hasMoc3 = contents.contains { $0.pathExtension.lowercased() == "moc3" }
        return hasModel3 && hasMoc3
    }

    static func findModelFiles(in url: URL) -> [CubismModelFiles] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return [] }

        let moc3ByBase = Dictionary(
            contents.filter { $0.pathExtension.lowercased() == "moc3" }
                .map { ($0.deletingPathExtension().lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var results = [CubismModelFiles]()

        for file in contents where file.lastPathComponent.hasSuffix(".model3.json") {
            let baseName = String(file.lastPathComponent.dropLast(".model3.json".count))
            if let moc3 = moc3ByBase[baseName] {
                results.append(CubismModelFiles(modelJson: file, moc3: moc3))
            }
        }

        // Fallback: single model3.json + single moc3 with mismatched names
        if results.isEmpty {
            let model3s = contents.filter { $0.lastPathComponent.hasSuffix(".model3.json") }
            let moc3s = contents.filter { $0.pathExtension.lowercased() == "moc3" }
            if model3s.count == 1, moc3s.count == 1 {
                results.append(CubismModelFiles(modelJson: model3s[0], moc3: moc3s[0]))
            }
        }

        return results
    }
}
