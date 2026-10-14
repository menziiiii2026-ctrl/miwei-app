import Foundation

enum DishType: String, Codable, CaseIterable, Identifiable, Sendable {
    case meat
    case vegetable
    case staple

    var id: Self { self }

    var displayName: String {
        switch self {
        case .meat: "荤菜"
        case .vegetable: "素菜"
        case .staple: "主食"
        }
    }
}

enum MealPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast
    case lunch
    case dinner

    var id: Self { self }

    var displayName: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        }
    }
}

struct RatingSet: Codable, Equatable, Sendable {
    var satisfaction: Double = 0.5
    var health: Double = 0.5
    var flavor: Double = 0.5
    var freshness: Double = 0.5
}

struct ArchiveDishDraft: Sendable {
    let displayName: String
    let category: DishType
    let plateID: String
    let plateVersion: Int
    let originalImagePath: String
    let foodPNGPath: String
    let composedPNGPath: String
    let recordedAt: Date
    let mealPeriod: MealPeriod?
    let recipeURL: URL?
    let ratings: RatingSet
}

struct DishArchiveInput: Sendable {
    let displayName: String
    let category: DishType
    let plate: PlateCatalogItem
    let plateCatalogVersion: Int
    let originalJPEGData: Data
    let foodPNGData: Data
    let recordedAt: Date
    let mealPeriod: MealPeriod?
    let recipeURL: URL?
    let ratings: RatingSet
}

struct DishSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let category: DishType
    let coverImagePath: String
    let tastingCount: Int
    let latestRecordAt: Date
}

struct TastingSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let dishID: UUID
    let dishDisplayName: String
    let dishCategory: DishType
    let ordinal: Int
    let plateID: String
    let plateVersion: Int
    let originalImagePath: String
    let foodPNGPath: String
    let composedPNGPath: String
    let recordedAt: Date
    let mealPeriod: MealPeriod?
    let recipeURL: URL?
    let ratings: RatingSet
}

enum RecordDeletionChoice: Equatable, Sendable {
    case currentTasting
    case entireDish
}

struct DeletionResult: Equatable, Sendable {
    let removedMediaPaths: Set<String>
    let deletedEntireDish: Bool
}
