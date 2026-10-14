import Foundation

struct CollageTemplateCatalog: Decodable, Equatable, Sendable {
    let version: String
    let canvasContract: String
    let assetRoot: String
    let exportRatio: String
    let templates: [CollageTemplateDescriptor]

    enum CodingKeys: String, CodingKey {
        case version
        case canvasContract = "canvas_contract"
        case assetRoot = "asset_root"
        case exportRatio = "export_ratio"
        case templates
    }

    func eligibleTemplates(foodCount: Int) -> [CollageTemplateDescriptor] {
        templates.filter { $0.supportedCount.contains(foodCount) }
    }
}

struct CollageTemplateDescriptor: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let code: String
    let supportedCount: ClosedRange<Int>
    let source: String
    let family: String
    let subjectMode: String
    let backgroundMode: String
    let textRoles: [String]
    let assetGroups: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case count
        case source
        case family
        case subjectMode = "subject_mode"
        case backgroundMode = "background_mode"
        case textRoles = "text_roles"
        case assetGroups = "asset_groups"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let count = try container.decode([Int].self, forKey: .count)
        guard count.count == 2, count[0] > 0, count[0] <= count[1] else {
            throw DecodingError.dataCorruptedError(
                forKey: .count,
                in: container,
                debugDescription: "Template count must contain a valid inclusive lower and upper bound."
            )
        }

        id = try container.decode(String.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        supportedCount = count[0]...count[1]
        source = try container.decode(String.self, forKey: .source)
        family = try container.decode(String.self, forKey: .family)
        subjectMode = try container.decode(String.self, forKey: .subjectMode)
        backgroundMode = try container.decode(String.self, forKey: .backgroundMode)
        textRoles = try container.decode([String].self, forKey: .textRoles)
        assetGroups = try container.decode([String].self, forKey: .assetGroups)
    }
}

protocol CollageTemplateCatalogLoading {
    func loadCatalog() throws -> CollageTemplateCatalog
}

struct BundledCollageTemplateCatalogLoader: CollageTemplateCatalogLoading {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadCatalog() throws -> CollageTemplateCatalog {
        guard let url = bundle.url(
            forResource: "template-catalog.v1",
            withExtension: "json",
            subdirectory: "app-contract"
        ) else {
            throw CollageGenerationError.missingTemplateCatalog
        }

        do {
            return try JSONDecoder().decode(
                CollageTemplateCatalog.self,
                from: Data(contentsOf: url, options: .mappedIfSafe)
            )
        } catch let error as CollageGenerationError {
            throw error
        } catch {
            throw CollageGenerationError.invalidTemplateCatalog
        }
    }
}
