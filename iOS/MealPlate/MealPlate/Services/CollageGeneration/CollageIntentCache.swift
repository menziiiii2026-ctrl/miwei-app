import CryptoKit
import Foundation

enum CollageInputFingerprint {
    static func make(for input: CollageCompositionInput) -> String {
        var parts = [
            input.period.rawValue,
            String(input.periodStart.timeIntervalSince1970),
            String(input.periodEnd.timeIntervalSince1970),
            input.templateCatalogVersion
        ]
        parts.append(contentsOf: input.foods.map {
            "\($0.id.uuidString)|\($0.plateID)|\($0.plateVersion)|\($0.recordedAt.timeIntervalSince1970)"
        })
        parts.append(contentsOf: input.backgroundCandidates.map(\.id).sorted())
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\n").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class CollageIntentCache {
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        directoryURL = applicationSupport.appending(
            path: "MealPlate/Collages/IntentCache",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func load(fingerprint: String) -> CollageCompositionIntent? {
        let url = directoryURL.appending(path: "\(fingerprint).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CollageCompositionIntent.self, from: data)
    }

    func save(_ intent: CollageCompositionIntent, fingerprint: String) {
        let url = directoryURL.appending(path: "\(fingerprint).json")
        guard let data = try? encoder.encode(intent) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

struct CachingCollageIntentProvider: CollageIntentProviding {
    let upstream: any CollageIntentProviding
    let cache: CollageIntentCache

    func makeIntent(
        for input: CollageCompositionInput,
        allowedTemplates: [CollageTemplateDescriptor]
    ) async throws -> CollageCompositionIntent {
        let fingerprint = CollageInputFingerprint.make(for: input)
        if let cached = cache.load(fingerprint: fingerprint),
           cached.reason != "local-deterministic-fallback",
           Self.isAllowed(cached, input: input, templates: allowedTemplates) {
            return cached
        }

        let intent = try await upstream.makeIntent(for: input, allowedTemplates: allowedTemplates)
        if intent.reason != "local-deterministic-fallback" {
            cache.save(intent, fingerprint: fingerprint)
        }
        return intent
    }

    private static func isAllowed(
        _ intent: CollageCompositionIntent,
        input: CollageCompositionInput,
        templates: [CollageTemplateDescriptor]
    ) -> Bool {
        let templateCodes = Set(templates.map(\.code))
        let backgroundIDs = Set(input.backgroundCandidates.map(\.id))
        return intent.version == CollageCompositionIntent.currentVersion
            && intent.foodCount == input.foods.count
            && !intent.rankedTemplateCodes.isEmpty
            && intent.rankedTemplateCodes.allSatisfy(templateCodes.contains)
            && backgroundIDs.contains(intent.backgroundID)
    }
}
