import Foundation

protocol CollageIntentProviding: Sendable {
    func makeIntent(
        for input: CollageCompositionInput,
        allowedTemplates: [CollageTemplateDescriptor]
    ) async throws -> CollageCompositionIntent
}

struct LocalFallbackCollageIntentProvider: CollageIntentProviding {
    func makeIntent(
        for input: CollageCompositionInput,
        allowedTemplates: [CollageTemplateDescriptor]
    ) async throws -> CollageCompositionIntent {
        guard !input.foods.isEmpty else {
            throw CollageGenerationError.emptyInput
        }
        guard let template = allowedTemplates.first else {
            throw CollageGenerationError.noEligibleTemplate
        }

        let caption = input.foods.count == 1
            ? input.foods[0].dishName
            : "这些都是好好吃饭的记录"
        return CollageCompositionIntent(
            version: CollageCompositionIntent.currentVersion,
            foodCount: input.foods.count,
            rankedTemplateCodes: [template.code],
            backgroundID: input.backgroundCandidates.first?.id ?? "app-default",
            mood: .init(tags: ["日常", "真实"], accentColor: "#774D4D"),
            copy: .init(caption: caption, season: nil, date: nil),
            reason: "local-deterministic-fallback"
        )
    }
}

struct ResilientCollageIntentProvider: CollageIntentProviding {
    let primary: (any CollageIntentProviding)?
    let fallback: any CollageIntentProviding

    func makeIntent(
        for input: CollageCompositionInput,
        allowedTemplates: [CollageTemplateDescriptor]
    ) async throws -> CollageCompositionIntent {
        if let primary,
           let intent = try? await primary.makeIntent(
               for: input,
               allowedTemplates: allowedTemplates
           ),
           Self.isValid(intent, input: input, allowedTemplates: allowedTemplates) {
            return intent
        }

        let intent = try await fallback.makeIntent(
            for: input,
            allowedTemplates: allowedTemplates
        )
        guard Self.isValid(intent, input: input, allowedTemplates: allowedTemplates) else {
            throw CollageGenerationError.invalidIntent("fallback provider returned invalid data")
        }
        return intent
    }

    private static func isValid(
        _ intent: CollageCompositionIntent,
        input: CollageCompositionInput,
        allowedTemplates: [CollageTemplateDescriptor]
    ) -> Bool {
        let allowedCodes = Set(allowedTemplates.map(\.code))
        let allowedBackgroundIDs = Set(input.backgroundCandidates.map(\.id))
        let backgroundIsValid = allowedBackgroundIDs.isEmpty
            ? intent.backgroundID == "app-default"
            : allowedBackgroundIDs.contains(intent.backgroundID)
        return intent.version == CollageCompositionIntent.currentVersion
            && intent.foodCount == input.foods.count
            && (1...3).contains(intent.rankedTemplateCodes.count)
            && intent.rankedTemplateCodes.allSatisfy(allowedCodes.contains)
            && backgroundIsValid
            && (1...5).contains(intent.mood.tags.count)
            && intent.mood.accentColor.wholeMatch(of: /^#[0-9A-Fa-f]{6}$/) != nil
            && intent.copy.caption.map { $0.count <= 42 } ?? true
            && intent.copy.season.map { $0.count <= 24 } ?? true
            && intent.copy.date.map { $0.count <= 24 } ?? true
            && intent.reason.map { $0.count <= 240 } ?? true
    }
}

struct RemoteCollageIntentProvider: CollageIntentProviding {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func makeIntent(
        for input: CollageCompositionInput,
        allowedTemplates: [CollageTemplateDescriptor]
    ) async throws -> CollageCompositionIntent {
        let endpoint = baseURL.appending(path: "v1/collage-intent")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(
            RequestBody(
                input: input,
                allowedTemplateCodes: allowedTemplates.map(\.code)
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw CollageGenerationError.remoteRequestFailed
        }

        do {
            return try JSONDecoder().decode(CollageCompositionIntent.self, from: data)
        } catch {
            throw CollageGenerationError.invalidIntent("response does not match composition-intent.v1")
        }
    }

    private struct RequestBody: Encodable {
        let input: CollageCompositionInput
        let allowedTemplateCodes: [String]

        enum CodingKeys: String, CodingKey {
            case input
            case allowedTemplateCodes = "allowed_template_codes"
        }
    }
}

@MainActor
final class CollageGenerationPlanner {
    private let catalogLoader: any CollageTemplateCatalogLoading
    private let intentProvider: any CollageIntentProviding

    init(
        catalogLoader: any CollageTemplateCatalogLoading,
        intentProvider: any CollageIntentProviding
    ) {
        self.catalogLoader = catalogLoader
        self.intentProvider = intentProvider
    }

    func makePlan(for input: CollageCompositionInput) async throws -> CollageGenerationPlan {
        guard !input.foods.isEmpty else {
            throw CollageGenerationError.emptyInput
        }

        let catalog = try catalogLoader.loadCatalog()
        let eligible = catalog.eligibleTemplates(foodCount: input.foods.count)
        guard !eligible.isEmpty else {
            throw CollageGenerationError.unsupportedFoodCount(input.foods.count)
        }

        let intent = try await intentProvider.makeIntent(
            for: input,
            allowedTemplates: eligible
        )
        guard let selectedCode = intent.rankedTemplateCodes.first,
              let template = eligible.first(where: { $0.code == selectedCode }) else {
            throw CollageGenerationError.noEligibleTemplate
        }

        return CollageGenerationPlan(input: input, template: template, intent: intent)
    }
}
