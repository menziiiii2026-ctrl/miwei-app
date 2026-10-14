import Foundation

struct StoredCollagePreview: Sendable {
    let data: Data
    let inputFingerprint: String
    let generatedAt: Date
}

nonisolated struct StoredCollageScene: Codable, Sendable {
    static let currentVersion = "canvas-scene.v1"

    let version: String
    let inputFingerprint: String
    let templateCode: String?
    let generationReason: String?
    let isSplitBackground: Bool
    let splitFraction: Double
    let backgrounds: [Background]
    let layers: [Layer]
    let savedAt: Date

    struct Background: Codable, Sendable {
        let id: UUID
        let sourceID: String?
        let embeddedPNGData: Data?
        let offsetX: Double
        let offsetY: Double
        let scale: Double
        /// Optional so scenes saved before background opacity support remain decodable.
        let opacity: Double?
    }

    struct Layer: Codable, Sendable {
        let id: UUID
        let kind: String
        let assetReference: String?
        let embeddedPNGData: Data?
        let text: String
        let centerX: Double
        let centerY: Double
        let normalizedWidth: Double
        let normalizedHeight: Double?
        let scale: Double
        let contentScale: Double
        let contentOffsetX: Double
        let contentOffsetY: Double
        let rotationDegrees: Double
        let opacity: Double
        let zIndex: Int
        /// Optional so scenes saved before template edit permissions remain decodable.
        let isEditable: Bool?
        /// Optional so scenes saved before template delete permissions remain decodable.
        let isDeletable: Bool?
        let textFont: String
        let isTextBold: Bool
        /// Optional so scenes saved before italic support remain decodable.
        let isTextItalic: Bool?
        let textAlignment: String
        let textColor: Color
        let textBackground: Color?
        let textFrameHeight: Double?
        let textFontSizeRatio: Double?
        let textLineHeightMultiple: Double?
        let textMaximumLines: Int?
        let textOverflow: String?
    }

    struct Color: Codable, Sendable {
        let name: String
        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double
    }
}

actor CollageArtifactStore {
    private let previewDirectoryURL: URL
    private let sceneDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = applicationSupport.appending(
            path: "MealPlate/Collages",
            directoryHint: .isDirectory
        )
        previewDirectoryURL = rootURL.appending(
            path: "Previews",
            directoryHint: .isDirectory
        )
        sceneDirectoryURL = rootURL.appending(
            path: "Scenes",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: previewDirectoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sceneDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    func loadPreview(
        period: JournalCollagePeriod,
        intervalStart: Date
    ) -> StoredCollagePreview? {
        let base = fileBase(period: period, intervalStart: intervalStart)
        let imageURL = previewDirectoryURL.appending(path: "\(base).png")
        let metadataURL = previewDirectoryURL.appending(path: "\(base).json")
        guard let data = try? Data(contentsOf: imageURL),
              let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? decoder.decode(Metadata.self, from: metadataData) else {
            return nil
        }
        return StoredCollagePreview(
            data: data,
            inputFingerprint: metadata.inputFingerprint,
            generatedAt: metadata.generatedAt
        )
    }

    func savePreview(
        _ data: Data,
        period: JournalCollagePeriod,
        intervalStart: Date,
        inputFingerprint: String
    ) throws {
        let base = fileBase(period: period, intervalStart: intervalStart)
        let imageURL = previewDirectoryURL.appending(path: "\(base).png")
        let metadataURL = previewDirectoryURL.appending(path: "\(base).json")
        let metadata = Metadata(
            inputFingerprint: inputFingerprint,
            generatedAt: .now
        )
        try data.write(to: imageURL, options: .atomic)
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
    }

    func loadScene(
        period: JournalCollagePeriod,
        intervalStart: Date,
        inputFingerprint: String
    ) -> StoredCollageScene? {
        let base = sceneFileBase(
            period: period,
            intervalStart: intervalStart,
            inputFingerprint: inputFingerprint
        )
        let url = sceneDirectoryURL.appending(path: "\(base).json")
        guard let data = try? Data(contentsOf: url),
              let scene = try? decoder.decode(StoredCollageScene.self, from: data),
              scene.version == StoredCollageScene.currentVersion,
              scene.inputFingerprint == inputFingerprint else {
            return nil
        }
        return scene
    }

    func saveScene(
        _ scene: StoredCollageScene,
        period: JournalCollagePeriod,
        intervalStart: Date
    ) throws {
        let base = sceneFileBase(
            period: period,
            intervalStart: intervalStart,
            inputFingerprint: scene.inputFingerprint
        )
        let url = sceneDirectoryURL.appending(path: "\(base).json")
        try encoder.encode(scene).write(to: url, options: .atomic)
    }

    private func fileBase(
        period: JournalCollagePeriod,
        intervalStart: Date
    ) -> String {
        "\(period.rawValue)-\(Int(intervalStart.timeIntervalSince1970))"
    }

    private func sceneFileBase(
        period: JournalCollagePeriod,
        intervalStart: Date,
        inputFingerprint: String
    ) -> String {
        "\(fileBase(period: period, intervalStart: intervalStart))-\(inputFingerprint)"
    }

    private struct Metadata: Codable {
        let inputFingerprint: String
        let generatedAt: Date
    }
}
