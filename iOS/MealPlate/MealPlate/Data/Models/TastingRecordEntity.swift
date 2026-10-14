import Foundation
import SwiftData

@Model
final class TastingRecordEntity {
    @Attribute(.unique) var id: UUID
    var ordinal: Int
    var plateID: String
    var plateVersion: Int
    var originalImagePath: String
    var foodPNGPath: String
    var composedPNGPath: String
    var recordedAt: Date
    var mealPeriodRawValue: String?
    var recipeURLString: String?
    var satisfaction: Double
    var health: Double
    var flavor: Double
    var freshness: Double
    var createdAt: Date
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    var ownerID: String?
    var cloudFoodPNGPath: String?
    var cloudComposedPNGPath: String?
    var remoteVersion: Int = 0
    var lastSyncedAt: Date?
    var dish: DishProfileEntity?

    init(
        id: UUID = UUID(),
        ordinal: Int,
        draft: ArchiveDishDraft,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        ownerID: String? = nil,
        cloudFoodPNGPath: String? = nil,
        cloudComposedPNGPath: String? = nil,
        remoteVersion: Int = 0,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.ordinal = ordinal
        self.plateID = draft.plateID
        self.plateVersion = draft.plateVersion
        self.originalImagePath = draft.originalImagePath
        self.foodPNGPath = draft.foodPNGPath
        self.composedPNGPath = draft.composedPNGPath
        self.recordedAt = draft.recordedAt
        self.mealPeriodRawValue = draft.mealPeriod?.rawValue
        self.recipeURLString = draft.recipeURL?.absoluteString
        self.satisfaction = draft.ratings.satisfaction
        self.health = draft.ratings.health
        self.flavor = draft.ratings.flavor
        self.freshness = draft.ratings.freshness
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.ownerID = ownerID
        self.cloudFoodPNGPath = cloudFoodPNGPath
        self.cloudComposedPNGPath = cloudComposedPNGPath
        self.remoteVersion = remoteVersion
        self.lastSyncedAt = lastSyncedAt
    }

    var snapshot: TastingSnapshot? {
        guard let dish else { return nil }
        return TastingSnapshot(
            id: id,
            dishID: dish.id,
            dishDisplayName: dish.displayName,
            dishCategory: dish.category,
            ordinal: ordinal,
            plateID: plateID,
            plateVersion: plateVersion,
            originalImagePath: originalImagePath,
            foodPNGPath: foodPNGPath,
            composedPNGPath: composedPNGPath,
            recordedAt: recordedAt,
            mealPeriod: mealPeriodRawValue.flatMap(MealPeriod.init(rawValue:)),
            recipeURL: recipeURLString.flatMap(URL.init(string:)),
            ratings: RatingSet(
                satisfaction: satisfaction,
                health: health,
                flavor: flavor,
                freshness: freshness
            )
        )
    }
}
