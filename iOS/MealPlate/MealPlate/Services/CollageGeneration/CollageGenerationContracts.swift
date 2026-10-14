import Foundation

enum CollageRuntimeRevision {
    // Bump whenever manifest interpretation or scene rendering changes so an
    // already-flattened preview cannot mask an outdated editable scene.
    static let templateFingerprint = "template-catalog.v1|text-layout-compiler-2026-09-15.1|fixed-decoration-compiler-2026-09-16.3"
}

struct CollageCompositionInput: Codable, Equatable, Sendable {
    let period: JournalCollagePeriod
    let periodStart: Date
    let periodEnd: Date
    let foods: [CollageFoodInput]
    let backgroundCandidates: [CollageBackgroundCandidate]
    let localeIdentifier: String
    let templateCatalogVersion: String
}

struct CollageFoodInput: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let dishName: String
    let cutoutAssetReference: String
    let recordedAt: Date
    let plateID: String
    let plateVersion: Int
    let analysisImage: CollageAnalysisImage?
}

struct CollageBackgroundCandidate: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let assetReference: String
    let tags: [String]
    let analysisImage: CollageAnalysisImage?
}

struct CollageAnalysisImage: Codable, Equatable, Sendable {
    let mimeType: String
    let imageBase64: String
}

enum CollageEditorAssetLibrary {
    static let backgroundNames = [
        "collage-bg-clean-plate",
        "collage-bg-active",
        "collage-bg-nature-sea-blue",
        "collage-bg-nature-tree",
        "collage-bg-nature-tree-sky",
        "collage-bg-warm-bookstore",
        "collage-bg-store",
        "collage-bg-bar",
        "collage-bg-dark-light",
        "collage-bg-streetlight-1",
        "collage-bg-streetlight-2",
        "collage-bg-streetlight-3"
    ]

    static func backgroundTags(for id: String) -> [String] {
        if id.contains("clean-plate") { return ["洁净", "餐桌", "明亮"] }
        if id.contains("active") { return ["活力", "明快", "日常"] }
        if id.contains("sea-blue") { return ["海蓝", "清爽", "自然"] }
        if id.contains("tree-sky") { return ["树影", "天空", "通透"] }
        if id.contains("nature-tree") { return ["树木", "绿色", "自然"] }
        if id.contains("warm-bookstore") { return ["暖色", "书店", "文艺"] }
        if id.contains("store") { return ["店铺", "生活感", "暖色"] }
        if id.contains("bar") { return ["酒吧", "夜晚", "氛围感"] }
        if id.contains("dark-light") { return ["暗调", "光影", "质感"] }
        if id.contains("streetlight") { return ["街灯", "夜景", "电影感"] }
        return ["编辑器背景"]
    }
}

struct CollageCompositionIntent: Codable, Equatable, Sendable {
    static let currentVersion = "composition-intent.v1"

    let version: String
    let foodCount: Int
    let rankedTemplateCodes: [String]
    let backgroundID: String
    let mood: Mood
    let copy: Copy
    let reason: String?

    struct Mood: Codable, Equatable, Sendable {
        let tags: [String]
        let accentColor: String

        enum CodingKeys: String, CodingKey {
            case tags
            case accentColor = "accent_color"
        }
    }

    struct Copy: Codable, Equatable, Sendable {
        let caption: String?
        let season: String?
        let date: String?
    }

    enum CodingKeys: String, CodingKey {
        case version
        case foodCount = "food_count"
        case rankedTemplateCodes = "ranked_template_codes"
        case backgroundID = "background_id"
        case mood
        case copy
        case reason
    }
}

struct CollageGenerationPlan: Equatable, Sendable {
    let input: CollageCompositionInput
    let template: CollageTemplateDescriptor
    let intent: CollageCompositionIntent
}

enum CollageGenerationError: LocalizedError, Sendable {
    case emptyInput
    case unsupportedFoodCount(Int)
    case missingTemplateCatalog
    case invalidTemplateCatalog
    case noEligibleTemplate
    case invalidIntent(String)
    case remoteRequestFailed

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "当前时间范围没有可生成的菜品。"
        case let .unsupportedFoodCount(count):
            "当前模板库尚不支持 \(count) 道菜。"
        case .missingTemplateCatalog:
            "App 内缺少模板目录。"
        case .invalidTemplateCatalog:
            "模板目录无法解析。"
        case .noEligibleTemplate:
            "当前没有满足素材条件的模板。"
        case let .invalidIntent(reason):
            "AI 返回的拼贴意图不合法：\(reason)"
        case .remoteRequestFailed:
            "AI 拼贴服务暂时不可用。"
        }
    }
}

extension JournalCollagePeriod: Codable {}
